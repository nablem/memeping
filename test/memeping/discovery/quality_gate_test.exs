defmodule MemePing.Discovery.QualityGateTest do
  use ExUnit.Case, async: true

  alias MemePing.Discovery.QualityGate

  @healthy_attrs %{
    last_checked_at: nil,
    name: "Doge Killer",
    ticker: "DOGEK",
    created_on_chain_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(-2 * 3_600, :second),
    market_cap: 100_000.0,
    volume_6h: 5_000.0,
    liquidity: 20_000.0,
    boost: 0,
    website_url: "https://dogekiller.example",
    url: "https://dexscreener.com/solana/xyz",
    telegram_url: nil,
    discord_url: nil,
    x_url: nil,
    tiktok_url: nil
  }

  test "a healthy, first-seen token stays active" do
    assert QualityGate.evaluate(@healthy_attrs) == %{active: true, inactivity_reason: nil}
  end

  test "flags missing name/ticker only on first update" do
    attrs = %{@healthy_attrs | name: nil}

    assert QualityGate.evaluate(attrs) == %{
             active: false,
             inactivity_reason: "missing_name_or_ticker"
           }

    # Not first update (last_checked_at set) -> no longer checked.
    attrs = %{attrs | last_checked_at: ~N[2026-01-01 00:00:00]}
    assert QualityGate.evaluate(attrs).active == true
  end

  test "flags an invalid ticker format on first update" do
    attrs = %{@healthy_attrs | ticker: "WAY_TOO_LONG_TICKER"}

    assert %{active: false, inactivity_reason: "invalid_ticker_format"} =
             QualityGate.evaluate(attrs)
  end

  test "flags an implausible market cap for a brand-new pair" do
    attrs = %{
      @healthy_attrs
      | created_on_chain_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(-60, :second),
        market_cap: 60_000_000.0
    }

    assert %{active: false, inactivity_reason: "invalid_market_cap"} = QualityGate.evaluate(attrs)
  end

  test "flags market cap below the floor" do
    attrs = %{@healthy_attrs | market_cap: 1_000.0}

    assert %{active: false, inactivity_reason: "market_cap_below_2_5k"} =
             QualityGate.evaluate(attrs)
  end

  test "flags zero 6h volume" do
    attrs = %{@healthy_attrs | volume_6h: 0}
    assert %{active: false, inactivity_reason: "zero_volume_6h"} = QualityGate.evaluate(attrs)
  end

  test "flags a tiktok creator-profile link" do
    attrs = %{@healthy_attrs | tiktok_url: "https://www.tiktok.com/@dogekiller"}

    assert %{active: false, inactivity_reason: "tiktok_creator_profile"} =
             QualityGate.evaluate(attrs)
  end

  test "flags any discord url" do
    attrs = %{@healthy_attrs | discord_url: "https://discord.gg/abc123"}

    assert %{active: false, inactivity_reason: "discord_url_present"} =
             QualityGate.evaluate(attrs)
  end

  test "flags a telegram link with no website" do
    attrs = %{@healthy_attrs | telegram_url: "https://t.me/dogekiller", website_url: nil}

    assert %{active: false, inactivity_reason: "telegram_url_without_website"} =
             QualityGate.evaluate(attrs)
  end

  test "flags an X status/intent/grok link instead of a profile" do
    attrs = %{@healthy_attrs | x_url: "https://x.com/dogekiller/status/12345"}
    assert %{active: false, inactivity_reason: "x_post_url"} = QualityGate.evaluate(attrs)
  end

  test "flags low liquidity" do
    attrs = %{@healthy_attrs | liquidity: 500.0}
    assert %{active: false, inactivity_reason: "low_liquidity"} = QualityGate.evaluate(attrs)
  end

  test "flags an unusually high boost count" do
    attrs = %{@healthy_attrs | boost: 500}
    assert %{active: false, inactivity_reason: "high_boost"} = QualityGate.evaluate(attrs)
  end

  test "flags a pair older than the age limit" do
    attrs = %{
      @healthy_attrs
      | created_on_chain_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(-841 * 3_600, :second)
    }

    assert %{active: false, inactivity_reason: "age_above_840h"} = QualityGate.evaluate(attrs)
  end

  test "flags a suspicious website domain" do
    attrs = %{@healthy_attrs | website_url: "https://github.com/someuser/somerepo"}
    assert %{active: false, inactivity_reason: "suspicious_website"} = QualityGate.evaluate(attrs)
  end
end
