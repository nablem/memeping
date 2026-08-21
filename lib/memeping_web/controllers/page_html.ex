defmodule MemePingWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use MemePingWeb, :html

  alias MemePing.Accounts.Plan

  embed_templates "page_html/*"

  defp price_label(%{price_cents: 0}), do: "Free"
  defp price_label(%{price_cents: cents}), do: "$#{div(cents, 100)} / 30 days"

  defp limit_label(nil, label), do: "Unlimited #{label}s"
  defp limit_label(1, label), do: "1 #{label} max"
  defp limit_label(n, label), do: "#{n} #{label}s max"

  defp term_list_limit_label(0), do: "No forbidden term lists"
  defp term_list_limit_label(limit), do: limit_label(limit, "forbidden term list")
end
