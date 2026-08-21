defmodule MemePingWeb.PageControllerTest do
  use MemePingWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Catch every memecoin call"
  end
end
