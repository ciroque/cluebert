defmodule CluebertWeb.SetupLiveTest do
  use CluebertWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cluebert.{Boards, GameServer}

  defp create_board(name) do
    {:ok, board} =
      Boards.create_board(%{
        name: Cluebert.DataCase.unique_board_name(name),
        categories: [%{title: "T", clues: [%{prompt: "p", response: "r", value: 100}]}]
      })

    board
  end

  defp add_team(view, name) do
    view |> form("#team-form", team: %{name: name}) |> render_submit()
  end

  defp stop_game_on_exit(id) do
    on_exit(fn ->
      for {pid, _} <- Registry.lookup(Cluebert.GameRegistry, id) do
        DynamicSupervisor.terminate_child(Cluebert.GameSupervisor, pid)
      end
    end)
  end

  describe "boards" do
    test "lists boards with the first one chosen", %{conn: conn} do
      apple = create_board("Apple")
      zebra = create_board("Zebra")

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#board-#{apple.id}[aria-pressed=true]")
      assert has_element?(view, "#board-#{zebra.id}[aria-pressed=false]")
    end

    test "choosing a board selects it", %{conn: conn} do
      apple = create_board("Apple")
      zebra = create_board("Zebra")
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#board-#{zebra.id}") |> render_click()

      assert has_element?(view, "#board-#{zebra.id}[aria-pressed=true]")
      assert has_element?(view, "#board-#{apple.id}[aria-pressed=false]")
    end

    test "says so when there are no boards, and cannot start", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      add_team(view, "Red")
      add_team(view, "Blue")

      assert has_element?(view, "#no-boards")
      assert has_element?(view, "#start-game[disabled]")
    end
  end

  describe "teams" do
    setup do
      create_board("Apple")
      :ok
    end

    test "adds trimmed names in order", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      add_team(view, "  Red ")
      add_team(view, "Blue")

      assert has_element?(view, "#team-0", "Red")
      assert has_element?(view, "#team-1", "Blue")
      refute has_element?(view, "#teams-needed")
    end

    test "rejects duplicate and blank names", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      add_team(view, "Red")

      add_team(view, "red")
      assert has_element?(view, "#team-form", "That name is already taken")

      add_team(view, "  ")
      assert has_element?(view, "#team-form", "Enter a team name")

      refute has_element?(view, "#team-1")
    end

    test "flags a duplicate while typing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      add_team(view, "Red")

      view |> form("#team-form", team: %{name: "RED"}) |> render_change()

      assert has_element?(view, "#team-form", "That name is already taken")
    end

    test "removes a team", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      add_team(view, "Red")
      add_team(view, "Blue")

      view |> element("#remove-team-0") |> render_click()

      assert has_element?(view, "#team-0", "Blue")
      refute has_element?(view, "#team-1")
    end
  end

  describe "starting" do
    test "is disabled until there are two teams", %{conn: conn} do
      create_board("Apple")
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#start-game[disabled]")
      assert has_element?(view, "#teams-needed")

      add_team(view, "Red")
      assert has_element?(view, "#start-game[disabled]")
      assert has_element?(view, "#teams-needed")

      add_team(view, "Blue")
      refute has_element?(view, "#start-game[disabled]")
      refute has_element?(view, "#teams-needed")
    end

    test "with one team, a forced start shows an error and starts nothing", %{conn: conn} do
      create_board("Apple")
      {:ok, view, _html} = live(conn, ~p"/")
      add_team(view, "Red")

      render_hook(view, "start", %{})

      assert has_element?(view, "#flash-error", "Add at least 2 teams.")
    end

    test "starts a game with the teams and goes to its host screen", %{conn: conn} do
      board = create_board("Apple")
      {:ok, view, _html} = live(conn, ~p"/")
      add_team(view, "Red")
      add_team(view, "Blue")

      assert {:error, {:live_redirect, %{to: "/games/" <> rest}}} =
               view |> element("#start-game") |> render_click()

      id = String.replace_suffix(rest, "/host", "")
      stop_game_on_exit(id)

      assert {:ok, %{board: %{id: board_id}, game: game}} = GameServer.get(id)
      assert board_id == board.id
      assert game.phase == :selecting
      assert game.teams |> Map.values() |> Enum.map(& &1.name) |> Enum.sort() == ["Blue", "Red"]
    end

    test "coming from a finished game, announces the new game to it", %{conn: conn} do
      create_board("Apple")
      :ok = GameServer.subscribe("finished-game")
      {:ok, view, _html} = live(conn, ~p"/?from=finished-game")
      add_team(view, "Red")
      add_team(view, "Blue")

      assert {:error, {:live_redirect, %{to: "/games/" <> rest}}} =
               view |> element("#start-game") |> render_click()

      new_id = String.replace_suffix(rest, "/host", "")
      stop_game_on_exit(new_id)
      assert_receive {:next_game, "finished-game", ^new_id}
    end

    test "shows an error for a board with no clues", %{conn: conn} do
      {:ok, _} = Boards.create_board(%{name: Cluebert.DataCase.unique_board_name("Empty")})
      {:ok, view, _html} = live(conn, ~p"/")
      add_team(view, "Red")
      add_team(view, "Blue")

      view |> element("#start-game") |> render_click()

      assert has_element?(view, "#flash-error", "That board has no clues yet.")
    end
  end
end
