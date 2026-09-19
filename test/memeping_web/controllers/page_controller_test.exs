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
    software_application = Enum.find(json_ld, &(&1["@type"] == "SoftwareApplication"))

    assert Enum.map(software_application["offers"], & &1["price"]) == [0.0, 19.0, 39.0]
    refute String.contains?(Jason.encode!(software_application), "priceSpecification")
    refute html =~ "{raw(Jason.encode!(data))}"
  end
end
