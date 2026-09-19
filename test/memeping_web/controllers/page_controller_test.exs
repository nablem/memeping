defmodule MemePingWeb.PageControllerTest do
  use MemePingWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    json_ld_blocks =
      Regex.scan(~r/<script type="application\/ld\+json">\s*(.*?)\s*<\/script>/s, html,
        capture: :all_but_first
      )

    json_ld = Enum.map(json_ld_blocks, &Jason.decode!(hd(&1)))

    assert html =~ "Catch every memecoin call"
    assert html =~ ~s(<link rel="icon" href="/favicon.ico" type="image/x-icon">)
    assert length(json_ld) == 2
    assert Enum.any?(json_ld, &String.contains?(Jason.encode!(&1), "P30D"))
    refute html =~ "{raw(Jason.encode!(data))}"
  end
end
