defmodule MemePing.Notifications.CriteriaTest do
  use ExUnit.Case, async: true

  alias MemePing.Notifications.Criteria

  @now ~N[2026-09-02 12:00:00]

  defp token(attrs) do
    Map.merge(
      %{
        created_on_chain_at: NaiveDateTime.add(@now, -5 * 3_600, :second),
        market_cap: 50_000.0,
        liquidity: 10_000.0,
        volume_1h: 1_000.0,
        volume_6h: 2_000.0,
        volume_24h: 3_000.0,
        change_5m: 1.0,
        change_1h: 2.0,
        change_6h: 3.0,
        change_24h: 4.0,
        boost: 0,
        ath: 60_000.0
      },
      attrs
    )
  end

  test "matches when no ranges are configured" do
    assert Criteria.match?(token(%{}), %Criteria{}, @now)
  end

  test "matches when every set metric falls within range" do
    criteria = %Criteria{market_cap_min: 10_000, market_cap_max: 100_000, liquidity_min: 5_000}
    assert Criteria.match?(token(%{}), criteria, @now)
  end

  test "fails when a metric is below its min" do
    criteria = %Criteria{market_cap_min: 60_000}
    refute Criteria.match?(token(%{}), criteria, @now)
  end

  test "fails when a metric is above its max" do
    criteria = %Criteria{market_cap_max: 40_000}
    refute Criteria.match?(token(%{}), criteria, @now)
  end

  test "fails when the token has no value for a constrained metric" do
    criteria = %Criteria{liquidity_min: 1}
    refute Criteria.match?(token(%{liquidity: nil}), criteria, @now)
  end

  test "age_hours is derived from created_on_chain_at" do
    criteria = %Criteria{age_hours_min: 4, age_hours_max: 6}
    assert Criteria.match?(token(%{}), criteria, @now)

    criteria = %Criteria{age_hours_max: 1}
    refute Criteria.match?(token(%{}), criteria, @now)
  end

  test "boost defaults to 0 when nil" do
    criteria = %Criteria{boost_min: 0, boost_max: 0}
    assert Criteria.match?(token(%{boost: nil}), criteria, @now)
  end
end
