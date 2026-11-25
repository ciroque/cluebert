defmodule Cluebert.GameServerTest do
  use Cluebert.DataCase, async: true

  alias Cluebert.{Boards, Game, GameServer}

  defp create_board(categories \\ nil) do
    categories =
      categories ||
        [
          %{title: "A", clues: [%{prompt: "a1", response: "r", value: 100}]},
          %{
            title: "B",
            clues: [
              %{prompt: "b1", response: "r", value: 100},
              %{prompt: "b2", response: "r", value: 200}
            ]
          }
        ]

    name = "Board #{System.unique_integer([:positive])}"
    {:ok, board} = Boards.create_board(%{name: name, categories: categories})
    Boards.get_board!(board.id)
  end

  defp clue_ids(board), do: for(c <- board.categories, clue <- c.clues, do: clue.id)

  defp start_game(_context) do
    board = create_board()
    id = "test-#{System.unique_integer([:positive])}"
    start_supervised!({GameServer, id: id, board: board})
    :ok = GameServer.subscribe(id)
    %{id: id, board: board}
  end

  describe "a running game" do
    setup :start_game

    test "holds the board and a game built from its clue values", %{id: id, board: board} do
      assert {:ok, %{id: ^id, board: ^board, game: game}} = GameServer.get(id)
      assert game.phase == :setup

      expected = for c <- board.categories, clue <- c.clues, into: %{}, do: {clue.id, clue.value}
      assert game.clues == expected
    end

    test "broadcasts the new game after every successful change", %{id: id, board: board} do
      [a1, b1, _b2] = clue_ids(board)

      assert {:ok, game, red} = GameServer.add_team(id, "Red")
      assert_receive {:game_updated, ^id, ^game}

      assert {:ok, game, blue} = GameServer.add_team(id, "Blue")
      assert_receive {:game_updated, ^id, ^game}

      assert {:ok, game} = GameServer.shuffle_order(id, &Enum.reverse/1)
      assert game.team_order == [blue, red]
      assert_receive {:game_updated, ^id, ^game}

      assert {:ok, game} = GameServer.start(id)
      assert_receive {:game_updated, ^id, ^game}

      assert {:ok, game} = GameServer.select(id, blue, a1)
      assert_receive {:game_updated, ^id, ^game}

      assert {:ok, game} = GameServer.judge(id, :correct)
      assert game.scores[blue] == 100
      assert_receive {:game_updated, ^id, ^game}

      assert {:ok, _} = GameServer.select(id, blue, b1)
      assert {:ok, game} = GameServer.judge(id, :wrong)
      assert Game.current_team(game) == red
      assert_receive {:game_updated, ^id, ^game}

      assert {:ok, game} = GameServer.end_game(id)
      assert game.phase == :done
      assert_receive {:game_updated, ^id, ^game}

      assert {:ok, %{game: ^game}} = GameServer.get(id)
    end

    test "removing a team broadcasts", %{id: id} do
      {:ok, _, red} = GameServer.add_team(id, "Red")
      assert_receive {:game_updated, ^id, _}

      assert {:ok, game} = GameServer.remove_team(id, red)
      assert game.teams == %{}
      assert_receive {:game_updated, ^id, ^game}
    end

    test "returns rule errors unchanged and does not broadcast", %{id: id} do
      {:ok, %{game: before}} = GameServer.get(id)

      assert {:error, :no_teams} = GameServer.start(id)
      assert {:error, :wrong_phase} = GameServer.judge(id, :correct)
      assert {:error, :invalid_name} = GameServer.add_team(id, "  ")

      refute_receive {:game_updated, ^id, _}
      assert {:ok, %{game: ^before}} = GameServer.get(id)
    end

    test "keeps its copy of the board when the board changes in the database", %{
      id: id,
      board: board
    } do
      Repo.delete!(board)

      assert {:ok, %{board: ^board, game: game}} = GameServer.get(id)
      assert map_size(game.clues) == 3
    end

    test "is not restarted after a crash", %{id: id} do
      [{pid, _}] = Registry.lookup(Cluebert.GameRegistry, id)
      ref = Process.monitor(pid)

      Process.exit(pid, :kill)

      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
      assert {:error, :not_found} = GameServer.get(id)
    end
  end

  describe "an unknown game" do
    test "returns :not_found" do
      assert {:error, :not_found} = GameServer.get("no-such-game")
      assert {:error, :not_found} = GameServer.add_team("no-such-game", "Red")
      assert {:error, :not_found} = GameServer.end_game("no-such-game")
    end
  end

  describe "start_game/1" do
    test "starts a game for a board under the game supervisor" do
      board = create_board()

      assert {:ok, id} = GameServer.start_game(board.id)
      assert [{pid, _}] = Registry.lookup(Cluebert.GameRegistry, id)
      on_exit(fn -> DynamicSupervisor.terminate_child(Cluebert.GameSupervisor, pid) end)

      assert {:ok, %{board: loaded, game: %Game{phase: :setup}}} = GameServer.get(id)
      assert loaded.id == board.id
    end

    test "gives each game its own id" do
      board = create_board()

      {:ok, first} = GameServer.start_game(board.id)
      {:ok, second} = GameServer.start_game(board.id)

      on_exit(fn ->
        for id <- [first, second], [{pid, _}] <- [Registry.lookup(Cluebert.GameRegistry, id)] do
          DynamicSupervisor.terminate_child(Cluebert.GameSupervisor, pid)
        end
      end)

      assert first != second
    end

    test "rejects a board with no clues" do
      board = create_board([%{title: "Empty", clues: []}])

      assert {:error, :invalid_board} = GameServer.start_game(board.id)
    end
  end
end
