defmodule CluebertWeb.HostLiveTest do
  use CluebertWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cluebert.{Boards, GameServer}

  # Two categories of different lengths: A has two clues, B has one.
  defp start_game(%{conn: conn}) do
    {:ok, board} =
      Boards.create_board(%{
        name: Cluebert.DataCase.unique_board_name("Host"),
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

    id = "host-test-#{System.unique_integer([:positive])}"

    start_supervised!(
      {GameServer,
       id: id, board: board, team_names: ["Red", "Blue"], shuffle: &Function.identity/1}
    )

    {:ok, %{game: game}} = GameServer.get(id)
    [red, blue] = game.team_order

    {:ok, view, _html} = live(conn, ~p"/games/#{id}/host")

    %{view: view, id: id, a: a, b: b, a1: a1, a2: a2, b1: b1, red: red, blue: blue}
  end

  defp select(view, clue), do: view |> element("#clue-#{clue.id}") |> render_click()
  defp judge(view, result), do: view |> element("#judge-#{result}") |> render_click()

  describe "a running game" do
    setup :start_game

    test "shows the board, with an empty cell for the shorter category", ctx do
      %{view: view, a: a, b: b, a1: a1, a2: a2, b1: b1} = ctx

      assert has_element?(view, "#category-#{a.id}", "A")
      assert has_element?(view, "#category-#{b.id}", "B")
      assert has_element?(view, "#clue-#{a1.id}[data-state=available]", "100")
      assert has_element?(view, "#clue-#{a2.id}[data-state=available]", "200")
      assert has_element?(view, "#clue-#{b1.id}[data-state=available]")
      assert has_element?(view, "#empty-#{b.id}-1")
      refute has_element?(view, "#open-clue")
    end

    test "shows the play order with scores and the current team", %{view: view} = ctx do
      assert has_element?(view, "#team-#{ctx.red}[aria-current=true]", "Red")
      assert has_element?(view, "#team-#{ctx.blue}[aria-current=false]", "Blue")
      assert has_element?(view, "#team-#{ctx.red}", "0")
    end

    test "selecting a clue opens it with its prompt, response and judging buttons", ctx do
      %{view: view, a1: a1, a2: a2} = ctx

      select(view, a1)

      assert has_element?(view, "#clue-#{a1.id}[data-state=open]")
      assert has_element?(view, "#open-clue-prompt", "A one")
      assert has_element?(view, "#open-clue-response", "Answer A1")
      assert has_element?(view, "#clue-#{a1.id} #judge-correct")
      assert has_element?(view, "#clue-#{a1.id} #judge-wrong")
      assert has_element?(view, "#clue-#{a2.id}[data-state=locked][disabled]")
    end

    test "correct scores, checks off the clue and keeps the turn", ctx do
      %{view: view, a2: a2, red: red, blue: blue} = ctx

      select(view, a2)
      judge(view, "correct")

      assert has_element?(view, "#clue-#{a2.id}[data-state=answered]")
      assert has_element?(view, "#team-#{red}[aria-current=true]", "200")
      assert has_element?(view, "#team-#{blue}", "0")
      refute has_element?(view, "#open-clue")
    end

    test "wrong leaves the clue on the board and passes the turn", ctx do
      %{view: view, a1: a1, red: red, blue: blue} = ctx

      select(view, a1)
      judge(view, "wrong")

      assert has_element?(view, "#clue-#{a1.id}[data-state=available]")
      assert has_element?(view, "#team-#{blue}[aria-current=true]")
      assert has_element?(view, "#team-#{red}[aria-current=false]", "0")
    end

    test "answering every clue ends the game with final standings", ctx do
      %{view: view, a1: a1, a2: a2, b1: b1, red: red, blue: blue} = ctx

      select(view, a1)
      judge(view, "wrong")

      for clue <- [a2, b1, a1] do
        select(view, clue)
        judge(view, "correct")
      end

      assert has_element?(view, "#game-over")
      assert has_element?(view, "#final-standings #standing-#{blue}", "1. Blue")
      assert has_element?(view, "#final-standings #standing-#{red}", "2. Red")
      refute has_element?(view, "#end-game")
      assert has_element?(view, "#new-game")
    end

    test "end game freezes the scores and shows the standings", %{view: view} = ctx do
      select(view, ctx.a1)
      view |> element("#end-game") |> render_click()

      assert has_element?(view, "#game-over")
      assert has_element?(view, "#clue-#{ctx.a1.id}[data-state=locked]")
      refute has_element?(view, "#open-clue")
      refute has_element?(view, "#end-game")
    end

    test "tied teams share a place", %{view: view} = ctx do
      view |> element("#end-game") |> render_click()

      assert has_element?(view, "#standing-#{ctx.red}", "1. Red")
      assert has_element?(view, "#standing-#{ctx.blue}", "1. Blue")
    end

    test "follows changes made elsewhere", %{view: view, id: id} = ctx do
      {:ok, _} = GameServer.select(id, ctx.red, ctx.b1.id)

      _ = render(view)
      assert has_element?(view, "#open-clue-prompt", "B one")
    end

    test "catches up and explains when a move is no longer allowed", ctx do
      %{view: view, id: id, a1: a1, b1: b1} = ctx

      # Another screen opens a clue before this one's click arrives.
      {:ok, _} = GameServer.select(id, ctx.red, b1.id)
      render_click(view, "select", %{"clue" => to_string(a1.id)})

      assert has_element?(view, "#flash-error")
      assert has_element?(view, "#clue-#{b1.id}[data-state=open]")
    end

    test "goes home if the game is gone", %{view: view, id: id} do
      [{pid, _}] = Registry.lookup(Cluebert.GameRegistry, id)
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

      assert {:error, {:live_redirect, %{to: "/"}}} =
               render_click(view, "end_game", %{})
    end
  end

  describe "an unknown game" do
    test "redirects home", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => _}}}} =
               live(conn, ~p"/games/no-such-game/host")
    end
  end
end
