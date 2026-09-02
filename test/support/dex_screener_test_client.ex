defmodule MemePing.Discovery.DexScreenerTestClient do
  @moduledoc false

  @behaviour MemePing.Discovery.DexScreenerClient

  @impl true
  def latest_token_profiles do
    Application.get_env(:memeping, :dex_screener_test_result, {:ok, []})
  end
end
