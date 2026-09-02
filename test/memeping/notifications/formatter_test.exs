defmodule MemePing.Notifications.FormatterTest do
  use ExUnit.Case, async: true

  alias MemePing.Notifications.Formatter

  @now ~N[2026-09-02 12:00:00]

  test "formats title, description, metrics and a dexscreener link" do
    token = %{
      ticker: "DOGEK",
      name: "Doge Killer",
      description: "Killing dogecoins since 2021",
      market_cap: 1_500_000.0,
      volume_1h: 25_000.0,
      change_1h: 12.5,
      created_on_chain_at: NaiveDateTime.add(@now, -2 * 3_600, :second),
      url: "https://dexscreener.com/solana/xyz"
    }

    message = Formatter.format(token, @now)

    assert message =~ "$DOGEK — Doge Killer"
    assert message =~ "Killing dogecoins since 2021"
    assert message =~ "Market Cap: $1.50M"
    assert message =~ "1h Volume: $25K"
    assert message =~ "1h Change: +12.50%"
    assert message =~ "Age: 2 hours"
    assert message =~ ~s(<a href="https://dexscreener.com/solana/xyz">DEX Screener</a>)
  end

  test "falls back to an 'Unknown token' title with no name or ticker" do
    message = Formatter.format(%{}, @now)
    assert message =~ "Unknown token"
  end

  test "escapes HTML-sensitive characters" do
    message = Formatter.format(%{name: "<script>alert(1)</script>", ticker: nil}, @now)
    refute message =~ "<script>"
    assert message =~ "&lt;script&gt;"
  end

  test "omits the urls line when there is no dexscreener url" do
    message = Formatter.format(%{ticker: "ABC"}, @now)
    refute message =~ "DEX Screener"
  end
end
