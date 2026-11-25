defmodule CluebertWeb.BoardLiveTest do
  use CluebertWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cluebert.{Boards, GameServer}

  # Two categories of different lengths: A has two clues, B has one.
  defp start_game(%{conn: conn}) do
    {:ok, board} =
      Boards.create_board(Cluebert.DataCase.unique_collection(), %{
        name: Cluebert.DataCase.unique_board_name("Player"),
        categories: [
          %{
            title: "A",
            clues: [
              %{prompt: "A one", response: "Answer A1", value: 100},
              %{prompt: "A two", response: "Answer A2", value: 200}
            ]
          },
          %{title: "B", clues: [%{prompt: "B one", response: "Answer B1", value: 100}]}
        ]
      })

    board = Boards.get_board!(board.id)
    [a, b] = board.categories
    [a1, a2] = a.clues
    [b1] = b.clues

    id = "board-test-#{System.unique_integer([:positive])}"

    start_supervised!(
      {GameServer,
       id: id, board: board, team_names: ["Red", "Blue"], shuffle: &Function.identity/1}
    )

    {:ok, %{game: game}} = GameServer.get(id)
    [red, blue] = game.team_order

    {:ok, view, _html} = live(conn, ~p"/games/#{id}")

    %{view: view, id: id, b: b, a1: a1, a2: a2, b1: b1, red: red, blue: blue}
  end

  # Board changes arrive as broadcasts; render/1 waits for them to be handled.
  defp play(view, fun) do
    fun.()
    _ = render(view)
    view
  end

  describe "a running game" do
    setup :start_game

    test "shows the board, scoreboard and current team, with no header", ctx do
      %{view: view, b: b, a1: a1, red: red, blue: blue} = ctx

      assert has_element?(view, "#board #clue-#{a1.id}[data-state=available]", "100")
      assert has_element?(view, "#empty-#{b.id}-1")
      assert has_element?(view, "#team-#{red}[aria-current=true]", "Red")
      assert has_element?(view, "#team-#{blue}[aria-current=false]", "Blue")
      refute has_element?(view, "header")
    end

    test "offers a full-screen button", %{view: view} do
      assert has_element?(view, ~s(#fullscreen-button[phx-hook$="Fullscreen"]))
    end

    test "is display only", %{view: view} do
      refute has_element?(view, "#board button")
      refute has_element?(view, "#end-game")
    end

    test "shows the open clue's prompt but never its response", ctx do
      %{view: view, id: id, a1: a1, red: red} = ctx

      play(view, fn -> GameServer.select(id, red, a1.id) end)

      assert has_element?(view, "#open-clue-prompt", "A one")
      assert has_element?(view, "#clue-#{a1.id}[data-state=open]")
      refute has_element?(view, "#board-screen", "Answer A1")
      refute has_element?(view, "#open-clue-response")
    end

    test "checks off correct answers and updates scores", ctx do
      %{view: view, id: id, a2: a2, red: red} = ctx

      play(view, fn ->
        GameServer.select(id, red, a2.id)
        GameServer.judge(id, :correct)
      end)

      assert has_element?(view, "#clue-#{a2.id}[data-state=answered]")
      assert has_element?(view, "#team-#{red}[aria-current=true]", "200")
      refute has_element?(view, "#open-clue")
    end

    test "passes the turn on an incorrect answer", ctx do
      %{view: view, id: id, a1: a1, red: red, blue: blue} = ctx

      play(view, fn ->
        GameServer.select(id, red, a1.id)
        GameServer.judge(id, :wrong)
      end)

      assert has_element?(view, "#clue-#{a1.id}[data-state=available]")
      assert has_element?(view, "#team-#{blue}[aria-current=true]")
    end

    test "shows the final standings when the game ends", ctx do
      %{view: view, id: id, red: red, blue: blue} = ctx

      play(view, fn -> GameServer.end_game(id) end)

      assert has_element?(view, "#game-over #standing-#{red}", "1. Red")
      assert has_element?(view, "#game-over #standing-#{blue}", "1. Blue")
    end

    test "switches to the next game when the host starts one", %{view: view, id: id} do
      GameServer.announce_next_game(id, "the-next-game")

      assert_redirect(view, "/games/the-next-game")
    end

    test "says so when the game stops", %{view: view, id: id} do
      [{pid, _}] = Registry.lookup(Cluebert.GameRegistry, id)
      ref = Process.monitor(pid)
      stop_supervised!(GameServer)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}

      assert has_element?(view, "#game-missing")
      refute has_element?(view, "#board")
    end
  end

  describe "an unknown game" do
    test "says so instead of redirecting", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/games/no-such-game")

      assert has_element?(view, "#game-missing")
    end
  end
end
