defmodule CluebertWeb.HomeLiveTest do
  use CluebertWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "GET / renders the home LiveView", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#home")
  end
end
