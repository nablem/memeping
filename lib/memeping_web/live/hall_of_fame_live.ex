defmodule MemePingWeb.HallOfFameLive do
  use MemePingWeb, :live_view

  alias MemePing.Discovery

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_tab={:hall_of_fame}>
      <section aria-labelledby="hall-of-fame-heading" class="space-y-6">
        <div class="space-y-1">
          <h1 id="hall-of-fame-heading" class="text-2xl font-semibold">Hall of Fame</h1>

          <p class="text-sm text-base-content/70">
            Active tokens with at least 500K MC ATH that have held above 20% of their peak.
          </p>
        </div>

        <p :if={@tokens == []} id="hall-of-fame-empty" class="py-10 text-sm text-base-content/70">
          No tokens meet the Hall of Fame criteria yet.
        </p>

        <div
          :if={@tokens != []}
          id="hall-of-fame-tokens"
          class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-5"
        >
          <article
            :for={token <- @tokens}
            id={"hall-of-fame-token-#{token.id}"}
            class="overflow-hidden border border-base-300 bg-base-100"
          >
            <div class="aspect-square bg-base-200">
              <img
                :if={token.icon}
                src={token.icon}
                alt={"#{token.name || token.ticker || "Token"} token image"}
                class="size-full object-cover"
              />
              <div
                :if={!token.icon}
                class="flex size-full items-center justify-center text-base-content/35"
              >
                <.icon name="hero-photo" class="size-10" />
              </div>
            </div>

            <div class="space-y-3 p-3">
              <div class="min-w-0">
                <p class="truncate text-sm font-semibold">{token.name || "Unnamed token"}</p>

                <p class="truncate font-mono text-xs text-base-content/65">{ticker(token.ticker)}</p>
              </div>

              <div>
                <p class="text-xs text-base-content/60">ATH</p>

                <p class="font-semibold">{format_market_cap(token.ath)} MC</p>
              </div>

              <div>
                <p class="text-xs text-base-content/60">Current MC</p>

                <div class="flex items-center gap-1.5">
                  <p class="text-sm font-medium">{format_market_cap(token.market_cap)} MC</p>

                  <span class={change_class(token.change_24h)}>
                    <.icon name={change_icon(token.change_24h)} class="size-3.5" /> {format_change(
                      token.change_24h
                    )}
                  </span>
                </div>
              </div>
            </div>
          </article>
        </div>
      </section>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :tokens, Discovery.hall_of_fame_tokens())}
  end

  defp ticker(nil), do: "$-"

  defp ticker(ticker) do
    if String.starts_with?(ticker, "$") do
      ticker
    else
      "$#{ticker}"
    end
  end

  defp format_market_cap(nil), do: "-"

  defp format_market_cap(value) when value >= 1_000_000,
    do: format_compact(value / 1_000_000, "M")

  defp format_market_cap(value) when value >= 1_000, do: format_compact(value / 1_000, "K")
  defp format_market_cap(value), do: format_compact(value, "")

  defp format_compact(value, suffix) do
    value
    |> :erlang.float_to_binary(decimals: 1)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
    |> Kernel.<>(suffix)
  end

  defp change_icon(value) when is_number(value) and value < 0, do: "hero-arrow-trending-down"
  defp change_icon(_value), do: "hero-arrow-trending-up"

  defp change_class(value) when is_number(value) and value < 0,
    do: "flex items-center gap-0.5 text-xs text-error"

  defp change_class(_value), do: "flex items-center gap-0.5 text-xs text-success"

  defp format_change(nil), do: "-"
  defp format_change(value), do: "#{format_compact(abs(value), "")}%"
end
