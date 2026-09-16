defmodule MemePing.Discovery.HallOfFameTest do
  use MemePing.DataCase

  alias MemePing.Discovery
  alias MemePing.Discovery.Token

  test "lists only active tokens that meet the ATH and drawdown thresholds" do
    qualifying = insert_token!(%{token_address: "Eligible", ath: 750_000, market_cap: 200_000})
    lower_ath = insert_token!(%{token_address: "LowerAth", ath: 500_000, market_cap: 100_000})
    insert_token!(%{token_address: "TooLowAth", ath: 499_999, market_cap: 499_999})
    insert_token!(%{token_address: "Rugged", ath: 600_000, market_cap: 119_999})
    insert_token!(%{token_address: "Inactive", active: false, ath: 900_000, market_cap: 900_000})

    assert Enum.map(Discovery.hall_of_fame_tokens(), & &1.id) == [qualifying.id, lower_ath.id]
  end

  test "orders by ATH descending and limits the list to ten tokens" do
    for index <- 1..11 do
      insert_token!(%{
        token_address: "Token#{index}",
        ath: index * 500_000,
        market_cap: index * 100_000
      })
    end

    results = Discovery.hall_of_fame_tokens()

    assert length(results) == 10
    assert Enum.map(results, & &1.ath) == Enum.to_list(11..2//-1) |> Enum.map(&(&1 * 500_000))
  end

  defp insert_token!(attrs) do
    %Token{}
    |> Token.changeset(Map.merge(%{active: true, chain_id: "solana"}, attrs))
    |> Repo.insert!()
  end
end
