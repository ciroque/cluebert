defmodule CluebertWeb.HealthControllerTest do
  use CluebertWeb.ConnCase, async: true

  test "GET /health answers ok without a session", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert text_response(conn, 200) == "ok"
    assert get_resp_header(conn, "set-cookie") == []
  end
end
