defmodule MemePing.Discovery do
  @moduledoc """
  Discovery pipeline: DEX Screener token recording (`Recorder`) and metrics
  refresh (`Updater`).
  """

  import Ecto.Query

  alias MemePing.Discovery.Token
  alias MemePing.Repo

  @doc """
  Prints the most recently touched tokens for a quick eyeball check from
  `iex -S mix` while the Recorder/Updater are running.

      iex> MemePing.Discovery.recap()
      iex> MemePing.Discovery.recap(50)
  """
  @spec recap(pos_integer()) :: :ok
  def recap(limit \\ 20) do
    Token
    |> order_by(desc: :updated_at)
    |> limit(^limit)
    |> Repo.all()
    |> print_recap()
  end

  defp print_recap([]), do: IO.puts("No tokens recorded yet.")

  defp print_recap(tokens) do
    Enum.each(tokens, fn t ->
      IO.puts(
        "#{pad(t.chain_id, 10)} #{pad(t.token_address, 46)} #{pad(t.ticker || "-", 10)} " <>
          "active=#{t.active} reason=#{t.inactivity_reason || "-"} mcap=#{fmt(t.market_cap)} " <>
          "liq=#{fmt(t.liquidity)} vol1h=#{fmt(t.volume_1h)} " <>
          "checked=#{t.last_checked_at || "-"} updated=#{t.updated_at}"
      )
    end)
  end

  defp pad(value, len), do: String.pad_trailing(to_string(value), len)
  defp fmt(nil), do: "-"
  defp fmt(value), do: :erlang.float_to_binary(value * 1.0, decimals: 2)
end
