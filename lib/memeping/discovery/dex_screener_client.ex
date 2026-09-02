defmodule MemePing.Discovery.DexScreenerClient do
  @moduledoc """
  Behaviour and dispatch module for fetching data from the DEX Screener API.
  """

  @callback latest_token_profiles() :: {:ok, [map()]} | {:error, term()}

  @spec latest_token_profiles() :: {:ok, [map()]} | {:error, term()}
  def latest_token_profiles, do: implementation().latest_token_profiles()

  defp implementation do
    Application.get_env(:memeping, :dex_screener_client, MemePing.Discovery.DexScreenerHTTPClient)
  end
end
