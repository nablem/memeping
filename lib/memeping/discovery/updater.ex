defmodule MemePing.Discovery.Updater do
  @moduledoc """
  Periodically refreshes metrics for active tokens across all supported chains.

  Ported from `Bentley.Updater`, with two differences:
    * multi-chain: the DEX Screener "tokens" details endpoint is per-chain
      (`tokens/v1/{chainId}/{addresses}`), so due tokens are grouped by chain
      before fetching;
    * batched: that endpoint accepts up to 30 comma-separated addresses per
      request, so same-chain tokens are fetched together instead of one
      request per token, to stay well within the shared rate limit;
    * no sniper/activity coupling (`Bentley.Activator` / `SniperPosition` are
      dropped entirely — MemePing never opens positions), replaced by the
      notifier-independent `MemePing.Discovery.QualityGate`;
    * chain-relevance filtering: only chains with at least one enabled
      notifier are fetched (`MemePing.Notifications.active_chains/0`),
      re-checked live every tick.
  """
  use GenServer
  require Logger

  import Ecto.Query

  alias MemePing.Discovery.QualityGate
  alias MemePing.Discovery.RateLimiter
  alias MemePing.Discovery.Token
  alias MemePing.Notifications
  alias MemePing.Repo

  @details_api_base_url "https://api.dexscreener.com/tokens/v1"
  @max_addresses_per_request 30
  @default_update_interval :timer.minutes(1)
  @default_batch_size 45

  @high_volume_threshold 1_000.0
  @age_fast_hours 10.0
  @age_short_hours 24.0
  @age_medium_hours 72.0
  @age_long_hours 240.0

  @fast_refresh_interval :timer.minutes(3)
  @short_refresh_interval :timer.minutes(5)
  @medium_refresh_interval :timer.minutes(15)
  @long_refresh_interval :timer.minutes(60)
  @very_long_refresh_interval :timer.hours(3)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_update(0)
    {:ok, %{interval: @default_update_interval, batch_size: @default_batch_size}}
  end

  @impl true
  def handle_info(:update, state) do
    Logger.info("[Updater] Refreshing metrics for active tokens...")

    state.batch_size
    |> due_tokens()
    |> Enum.group_by(& &1.chain_id, & &1.token_address)
    |> Enum.each(fn {chain_id, addresses} -> fetch_and_update_chain(chain_id, addresses) end)

    schedule_update(state.interval)
    {:noreply, state}
  end

  def due_tokens(limit \\ @default_batch_size, now \\ current_time()) do
    case Notifications.active_chains() do
      [] ->
        []

      active_chains ->
        Token
        |> where([t], t.active == true and t.chain_id in ^active_chains)
        |> select([t], %{
          chain_id: t.chain_id,
          token_address: t.token_address,
          created_on_chain_at: t.created_on_chain_at,
          last_checked_at: t.last_checked_at,
          volume_1h: t.volume_1h
        })
        |> Repo.all()
        |> Enum.filter(&due_by_policy?(&1, now))
        |> Enum.sort_by(&overdue_ratio(&1, now), :desc)
        |> Enum.take(limit)
    end
  end

  def cutoff_for(now \\ current_time(), interval_ms \\ @default_update_interval) do
    NaiveDateTime.add(now, -div(interval_ms, 1_000), :second)
  end

  def update_interval_for(age_hours, volume_1h) do
    cond do
      fast_refresh?(age_hours, volume_1h) ->
        @fast_refresh_interval

      age_hours < @age_short_hours ->
        @short_refresh_interval

      age_hours < @age_medium_hours ->
        @medium_refresh_interval

      age_hours < @age_long_hours ->
        @long_refresh_interval

      true ->
        @very_long_refresh_interval
    end
  end

  def update_token_from_details(chain_id, token_address, details)
      when is_binary(chain_id) and is_binary(token_address) and is_map(details) do
    socials = get_in(details, ["info", "socials"]) || []

    attrs = %{
      url: details["url"],
      website_url: first_website_url(details),
      x_url: social_url(socials, "twitter"),
      telegram_url: social_url(socials, "telegram"),
      tiktok_url: social_url(socials, "tiktok"),
      instagram_url: social_url(socials, "instagram"),
      discord_url: social_url(socials, "discord"),
      boost: normalize_integer(get_in(details, ["boosts", "active"])),
      created_on_chain_at: normalize_pair_created_at(details["pairCreatedAt"]),
      market_cap: normalize_number(details["marketCap"]),
      name: get_in(details, ["baseToken", "name"]),
      ticker: get_in(details, ["baseToken", "symbol"]),
      volume_1h: normalize_number(get_in(details, ["volume", "h1"])),
      volume_6h: normalize_number(get_in(details, ["volume", "h6"])),
      volume_24h: normalize_number(get_in(details, ["volume", "h24"])),
      change_5m: normalize_number(get_in(details, ["priceChange", "m5"])),
      change_1h: normalize_number(get_in(details, ["priceChange", "h1"])),
      change_6h: normalize_number(get_in(details, ["priceChange", "h6"])),
      change_24h: normalize_number(get_in(details, ["priceChange", "h24"])),
      liquidity: normalize_number(get_in(details, ["liquidity", "usd"])),
      icon: get_in(details, ["info", "imageUrl"]),
      last_checked_at: current_time()
    }

    case Repo.get_by(Token, chain_id: chain_id, token_address: token_address) do
      nil ->
        {:error, :token_not_found}

      token ->
        attrs = attrs |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()
        attrs = compute_ath(attrs, token)

        quality_attrs =
          token
          |> attrs_for_quality_gate(attrs)
          |> QualityGate.evaluate()

        attrs = Map.merge(attrs, quality_attrs)

        token
        |> Token.changeset(attrs)
        |> Repo.update()
    end
  end

  defp attrs_for_quality_gate(token, incoming_attrs) do
    token
    |> Map.from_struct()
    |> Map.drop([:__meta__, :id, :inserted_at, :updated_at])
    |> Map.merge(incoming_attrs)
    # QualityGate's first-update detection relies on the previous check timestamp.
    |> Map.put(:last_checked_at, token.last_checked_at)
  end

  @doc false
  def handle_details_response(chain_id, addresses, response) when is_binary(chain_id) do
    case response do
      {:ok, %{status: 200, body: pairs}} when is_list(pairs) ->
        pairs_by_address = best_pair_by_address(pairs)

        Enum.map(addresses, fn address ->
          case Map.fetch(pairs_by_address, address) do
            {:ok, details} ->
              case update_token_from_details(chain_id, address, details) do
                {:ok, token} -> {:ok, :updated, token}
                {:error, reason} -> {:error, reason}
              end

            :error ->
              case mark_token_inactive(chain_id, address, "token_undefined_per_api") do
                {:ok, token} -> {:ok, :inactivated, token}
                {:error, reason} -> {:error, reason}
              end
          end
        end)

      {:ok, %{status: 404}} ->
        Enum.map(addresses, fn address ->
          case mark_token_inactive(chain_id, address, "token_undefined_per_api") do
            {:ok, token} -> {:ok, :inactivated, token}
            {:error, reason} -> {:error, reason}
          end
        end)

      {:ok, %{status: 429}} ->
        Logger.warning("[Updater] DEX Screener rate limit reached (HTTP 429).")
        [{:error, :rate_limited}]

      {:ok, response} ->
        Logger.error(
          "[Updater] Unexpected response for #{chain_id}/#{inspect(addresses)}: #{inspect(response)}"
        )

        [{:error, :unexpected_response}]

      {:error, reason} ->
        Logger.error(
          "[Updater] API request failed for #{chain_id}/#{inspect(addresses)}: #{inspect(reason)}"
        )

        [{:error, reason}]
    end
  end

  # Multiple pairs (across DEXes) can exist for the same base token address;
  # keep the one with the highest liquidity as the representative pair.
  defp best_pair_by_address(pairs) do
    Enum.reduce(pairs, %{}, fn pair, acc ->
      address = get_in(pair, ["baseToken", "address"])

      if is_binary(address) do
        Map.update(acc, address, pair, fn current ->
          if pair_liquidity(pair) > pair_liquidity(current), do: pair, else: current
        end)
      else
        acc
      end
    end)
  end

  defp pair_liquidity(pair), do: normalize_number(get_in(pair, ["liquidity", "usd"])) || 0.0

  defp compute_ath(attrs, token) do
    case attrs[:market_cap] do
      market_cap when is_number(market_cap) ->
        ath =
          [token.ath, token.market_cap, market_cap]
          |> Enum.filter(&is_number/1)
          |> Enum.max()

        Map.put(attrs, :ath, ath)

      _ ->
        attrs
    end
  end

  defp mark_token_inactive(chain_id, token_address, reason) do
    case Repo.get_by(Token, chain_id: chain_id, token_address: token_address) do
      nil ->
        {:error, :token_not_found}

      token ->
        token
        |> Token.changeset(%{
          active: false,
          inactivity_reason: reason,
          last_checked_at: current_time()
        })
        |> Repo.update()
    end
  end

  defp fetch_and_update_chain(chain_id, addresses) do
    addresses
    |> Enum.chunk_every(@max_addresses_per_request)
    |> Enum.each(fn chunk ->
      url = "#{@details_api_base_url}/#{chain_id}/#{Enum.join(chunk, ",")}"
      response = RateLimiter.execute(fn -> Req.get(url) end)

      chain_id
      |> handle_details_response(chunk, response)
      |> Enum.each(&log_result(chain_id, &1))
    end)
  end

  defp log_result(chain_id, {:ok, :updated, token}),
    do: Logger.debug("[Updater] Refreshed #{chain_id}/#{token.token_address}")

  defp log_result(chain_id, {:ok, :inactivated, token}),
    do:
      Logger.info(
        "[Updater] Marked #{chain_id}/#{token.token_address} inactive: token_undefined_per_api"
      )

  defp log_result(chain_id, {:error, reason}),
    do: Logger.error("[Updater] Failed to persist a token on #{chain_id}: #{inspect(reason)}")

  defp normalize_number(value) when is_integer(value), do: value * 1.0
  defp normalize_number(value) when is_float(value), do: value
  defp normalize_number(_value), do: nil

  defp normalize_integer(value) when is_integer(value), do: value
  defp normalize_integer(value) when is_float(value), do: trunc(value)
  defp normalize_integer(_value), do: nil

  defp normalize_pair_created_at(value) when is_integer(value) do
    case DateTime.from_unix(value, :millisecond) do
      {:ok, datetime} -> DateTime.to_naive(datetime) |> NaiveDateTime.truncate(:second)
      _ -> nil
    end
  end

  defp normalize_pair_created_at(value) when is_float(value) do
    normalize_pair_created_at(round(value))
  end

  defp normalize_pair_created_at(_value), do: nil

  defp first_website_url(details) do
    details
    |> get_in(["info", "websites"])
    |> case do
      [%{"url" => url} | _] when is_binary(url) -> url
      _ -> nil
    end
  end

  defp social_url(socials, type) do
    Enum.find_value(socials, fn
      %{"type" => ^type, "url" => url} when is_binary(url) -> url
      _ -> nil
    end)
  end

  defp fast_refresh?(age_hours, volume_1h) do
    age_hours < @age_fast_hours or volume_1h > @high_volume_threshold
  end

  defp due_by_policy?(token, now) do
    age_hours = age_in_hours(token.created_on_chain_at, now)
    volume_1h = token.volume_1h || 0.0
    interval = update_interval_for(age_hours, volume_1h)

    token.last_checked_at == nil or
      NaiveDateTime.compare(token.last_checked_at, cutoff_for(now, interval)) in [:lt, :eq]
  end

  # Never-checked tokens always get maximum priority.
  defp overdue_ratio(%{last_checked_at: nil}, _now), do: 1.0e308

  defp overdue_ratio(token, now) do
    age_hours = age_in_hours(token.created_on_chain_at, now)
    volume_1h = token.volume_1h || 0.0
    interval_seconds = div(update_interval_for(age_hours, volume_1h), 1_000)
    NaiveDateTime.diff(now, token.last_checked_at, :second) / interval_seconds
  end

  defp age_in_hours(nil, _now), do: 0.0

  defp age_in_hours(created_on_chain_at, now) do
    NaiveDateTime.diff(now, created_on_chain_at, :second) / 3_600
  end

  defp current_time do
    NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
  end

  defp schedule_update(interval) do
    Process.send_after(self(), :update, interval)
  end
end
