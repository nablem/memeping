defmodule MemePing.Discovery.Recorder do
  @moduledoc """
  Periodically fetches latest token profiles from DEX Screener and records them.

  Ported from `Bentley.Recorder`, made multi-chain: instead of hardcoding
  `chainId == "solana"`, it keeps any profile whose chain is one we support
  (`MemePing.Notifications.Notifier.chains/0`), across a single shared poll.
  """
  use GenServer
  require Logger

  alias MemePing.Discovery.DexScreenerClient
  alias MemePing.Discovery.Token
  alias MemePing.Notifications.Notifier
  alias MemePing.Repo

  @poll_interval :timer.minutes(2)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_poll(0)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:poll, state) do
    Logger.info("[Recorder] Polling DEX Screener for latest profiles...")

    case DexScreenerClient.latest_token_profiles() do
      {:ok, profiles} ->
        profiles
        |> Enum.filter(fn p -> p["chainId"] in Notifier.chains() end)
        |> Enum.each(&process_token/1)

      {:error, :rate_limited} ->
        Logger.warning("[Recorder] DEX Screener rate limit reached (HTTP 429).")

      {:error, reason} ->
        Logger.error("[Recorder] API request failed: #{inspect(reason)}")
    end

    schedule_poll()

    {:noreply, state}
  end

  def process_token(data) do
    attrs = %{
      chain_id: data["chainId"],
      token_address: data["tokenAddress"],
      description: data["description"]
    }

    %Token{}
    |> Token.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:description, :updated_at]},
      conflict_target: [:chain_id, :token_address]
    )
    |> case do
      {:ok, _token} ->
        Logger.info(
          "[Recorder] Discovered/Updated token: #{data["chainId"]}/#{data["tokenAddress"]}"
        )

      {:error, changeset} ->
        Logger.error(
          "[Recorder] Failed to save token #{data["chainId"]}/#{data["tokenAddress"]}: #{inspect(changeset.errors)}"
        )
    end
  end

  defp schedule_poll(interval \\ @poll_interval) do
    Process.send_after(self(), :poll, interval)
  end
end
