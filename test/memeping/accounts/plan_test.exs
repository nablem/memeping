defmodule MemePing.Accounts.PlanTest do
  use ExUnit.Case, async: true

  alias MemePing.Accounts.Plan

  test "the Max plan allows up to 30 notifiers" do
    assert Plan.get!("max").notifier_limit == 30
  end
end
