defmodule MemePingWeb.HallOfFameLiveTest do
  use MemePingWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MemePing.Accounts.User
  alias MemePing.Discovery.Token
  alias MemePing.Repo

  setup %{conn: conn} do
    user = Repo.insert!(User.changeset(%User{}, %{}))
    conn = Plug.Test.init_test_session(conn, %{"user_id" => user.id})
    %{conn: conn}
  end

  test "displays qualifying tokens with compact market caps and ticker formatting", %{conn: conn} do
    token =
      insert_token!(%{
        token_address: "HallToken",
        name: "Hall Token",
        ticker: "$HALL",
        ath: 500_000,
        market_cap: 250_000,
        change_24h: -12.5,
        icon: "https://example.com/hall.png"
      })

    {:ok, view, _html} = live(conn, ~p"/hall-of-fame")

    assert has_element?(view, "#hall-of-fame-token-#{token.id}")

    assert has_element?(
             view,
             "#hall-of-fame-token-#{token.id} img[src='https://example.com/hall.png']"
           )

    assert render(view) =~ "500K MC"
    assert render(view) =~ "250K MC"
    assert render(view) =~ "$HALL"
    assert has_element?(view, "#hall-of-fame-token-#{token.id} .text-error")
  end

  test "shows an empty state when no tokens qualify", %{conn: conn} do
    insert_token!(%{token_address: "BelowThreshold", ath: 499_999, market_cap: 499_999})

    {:ok, view, _html} = live(conn, ~p"/hall-of-fame")

    assert has_element?(view, "#hall-of-fame-empty")
  end

  defp insert_token!(attrs) do
    %Token{}
    |> Token.changeset(Map.merge(%{active: true, chain_id: "solana"}, attrs))
    |> Repo.insert!()
  end
end
