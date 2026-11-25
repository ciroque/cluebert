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
    {:ok, board} = Boards.create_board(unique_collection(), %{name: name, categories: categories})
    Boards.get_board!(board.id)
  end

  defp clue_ids(board), do: for(c <- board.categories, clue <- c.clues, do: clue.id)

  defp start_game(_context) do
    board = create_board()
    id = "test-#{System.unique_integer([:positive])}"

    start_supervised!(
      {GameServer, id: id, board: board, team_names: ["Red", "Blue"], shuffle: &Enum.reverse/1}
    )

    :ok = GameServer.subscribe(id)
    %{id: id, board: board}
  end

  defp team_id(game, name) do
    Enum.find_value(game.teams, fn {id, team} -> team.name == name && id end)
  end

  describe "a running game" do
    setup :start_game

    test "starts already playing, with its teams in shuffled order", %{id: id, board: board} do
      assert {:ok, %{id: ^id, board: ^board, game: game}} = GameServer.get(id)
      assert game.phase == :selecting

      red = team_id(game, "Red")
      blue = team_id(game, "Blue")
      assert game.team_order == [blue, red]
      assert Game.current_team(game) == blue

      expected = for c <- board.categories, clue <- c.clues, into: %{}, do: {clue.id, clue.value}
      assert game.clues == expected
    end

    test "broadcasts the new game after every successful change", %{id: id, board: board} do
      [a1, b1, _b2] = clue_ids(board)
      {:ok, %{game: game}} = GameServer.get(id)
      red = team_id(game, "Red")
      blue = team_id(game, "Blue")

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

    test "returns rule errors unchanged and does not broadcast", %{id: id, board: board} do
      {:ok, %{game: before}} = GameServer.get(id)
      red = team_id(before, "Red")

      assert {:error, :wrong_phase} = GameServer.judge(id, :correct)
      assert {:error, :not_your_turn} = GameServer.select(id, red, hd(clue_ids(board)))

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

  describe "a finished game" do
    defp start_short_lived_game(ttl) do
      board = create_board()
      id = "finished-#{System.unique_integer([:positive])}"

      start_supervised!(
        {GameServer, id: id, board: board, team_names: ["Red", "Blue"], finished_ttl: ttl}
      )

      {:ok, ref} = GameServer.monitor(id)
      %{id: id, ref: ref}
    end

    test "stops itself once its time is up" do
      %{id: id, ref: ref} = start_short_lived_game(0)

      {:ok, _} = GameServer.end_game(id)

      assert_receive {:DOWN, ^ref, :process, _pid, :normal}
      assert {:error, :not_found} = GameServer.get(id)
    end

    test "stops after the last clue is answered, too" do
      %{id: id, ref: ref} = start_short_lived_game(0)
      {:ok, %{board: board, game: game}} = GameServer.get(id)

      for clue_id <- clue_ids(board) do
        {:ok, _} = GameServer.select(id, Game.current_team(game), clue_id)
        {:ok, _} = GameServer.judge(id, :correct)
      end

      assert_receive {:DOWN, ^ref, :process, _pid, :normal}
    end

    test "keeps running until then, for the next game to read" do
      %{id: id, ref: ref} = start_short_lived_game(:timer.hours(1))

      {:ok, _} = GameServer.end_game(id)

      assert {:ok, %{game: %Game{phase: :done}}} = GameServer.get(id)
      refute_received {:DOWN, ^ref, _, _, _}
    end
  end

  describe "monitor/1" do
    test "returns :not_found for an unknown game" do
      assert {:error, :not_found} = GameServer.monitor("no-such-game")
    end
  end

  describe "announce_next_game/2" do
    test "tells the old game's subscribers about the new game" do
      :ok = GameServer.subscribe("old-game")

      assert :ok = GameServer.announce_next_game("old-game", "new-game")
      assert_receive {:next_game, "old-game", "new-game"}
    end
  end

  describe "an unknown game" do
    test "returns :not_found" do
      assert {:error, :not_found} = GameServer.get("no-such-game")
      assert {:error, :not_found} = GameServer.judge("no-such-game", :correct)
      assert {:error, :not_found} = GameServer.end_game("no-such-game")
    end
  end

  describe "start_game/2" do
    test "starts a game for a board and teams under the game supervisor" do
      board = create_board()

      assert {:ok, id} = GameServer.start_game(board.id, ["Red", "Blue", "Gold"])
      assert [{pid, _}] = Registry.lookup(Cluebert.GameRegistry, id)
      on_exit(fn -> DynamicSupervisor.terminate_child(Cluebert.GameSupervisor, pid) end)

      assert {:ok, %{board: loaded, game: %Game{phase: :selecting} = game}} = GameServer.get(id)
      assert loaded.id == board.id
      assert game.teams |> Map.values() |> Enum.map(& &1.name) |> Enum.sort() == ~w(Blue Gold Red)
      assert length(game.team_order) == 3
    end

    test "gives each game its own id" do
      board = create_board()

      {:ok, first} = GameServer.start_game(board.id, ["Red", "Blue"])
      {:ok, second} = GameServer.start_game(board.id, ["Red", "Blue"])

      on_exit(fn ->
        for id <- [first, second], [{pid, _}] <- [Registry.lookup(Cluebert.GameRegistry, id)] do
          DynamicSupervisor.terminate_child(Cluebert.GameSupervisor, pid)
        end
      end)

      assert first != second
    end

    test "rejects a board with no clues" do
      board = create_board([%{title: "Empty", clues: []}])

      assert {:error, :invalid_board} = GameServer.start_game(board.id, ["Red", "Blue"])
    end

    test "rejects fewer than two teams and bad team names" do
      board = create_board()
      assert {:error, :too_few_teams} = GameServer.start_game(board.id, [])
      assert {:error, :too_few_teams} = GameServer.start_game(board.id, ["Red"])
      assert {:error, :duplicate_name} = GameServer.start_game(board.id, ["Red", "red"])
      assert {:error, :invalid_name} = GameServer.start_game(board.id, ["Red", " "])
    end
  end
end
