defmodule MemePing.Discovery.DexScreenerHTTPClient do
  @moduledoc false

  @behaviour MemePing.Discovery.DexScreenerClient

  alias MemePing.Discovery.RateLimiter

  @api_url "https://api.dexscreener.com/token-profiles/latest/v1"

  @impl true
  def latest_token_profiles do
    case RateLimiter.execute(fn -> Req.get(@api_url) end) do
      {:ok, %{status: 200, body: profiles}} when is_list(profiles) -> {:ok, profiles}
      {:ok, response} -> {:error, {:unexpected_response, response}}
      {:error, reason} -> {:error, reason}
    end
  end
end
