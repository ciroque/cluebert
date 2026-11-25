defmodule CluebertWeb.HostLiveTest do
  use CluebertWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cluebert.{Boards, GameServer}

  test "shows the play order of a running game", %{conn: conn} do
    {:ok, board} =
      Boards.create_board(%{
        name: Cluebert.DataCase.unique_board_name("Apple"),
        categories: [%{title: "T", clues: [%{prompt: "p", response: "r", value: 100}]}]
      })

    id = "host-test-#{System.unique_integer([:positive])}"

    start_supervised!(
      {GameServer, id: id, board: Boards.get_board!(board.id), team_names: ["Red", "Blue"]}
    )

    {:ok, view, _html} = live(conn, ~p"/games/#{id}/host")

    assert has_element?(view, "#play-order", "Red")
    assert has_element?(view, "#play-order", "Blue")
  end

  test "redirects home for an unknown game", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => _}}}} =
             live(conn, ~p"/games/no-such-game/host")
  end
end
