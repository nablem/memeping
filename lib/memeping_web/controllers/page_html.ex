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

  @doc """
  JSON-LD structured data describing MemePing and its plans, rendered as
  separate `<script type="application/ld+json">` blocks on the homepage.
  """
  def structured_data do
    [organization_json_ld(), software_application_json_ld()]
  end

  defp organization_json_ld do
    %{
      "@context" => "https://schema.org",
      "@type" => "Organization",
      "name" => "MemePing",
      "url" => absolute_url(~p"/"),
      "logo" => absolute_url(~p"/images/logo.png")
    }
  end

  defp software_application_json_ld do
    %{
      "@context" => "https://schema.org",
      "@type" => "SoftwareApplication",
      "name" => "MemePing",
      "description" =>
        "Real-time memecoin call alerts. MemePing monitors DEX Screener and sends matching " <>
          "calls straight to your Telegram based on your own chain, threshold, and " <>
          "forbidden-term filters.",
      "applicationCategory" => "FinanceApplication",
      "operatingSystem" => "Web",
      "offers" => Enum.map(Plan.all(), &plan_offer_json_ld/1)
    }
  end

  defp plan_offer_json_ld(plan) do
    %{
      "@type" => "Offer",
      "name" => plan.name,
      "price" => plan.price_cents / 100,
      "priceCurrency" => "USD",
      "priceSpecification" => %{
        "@type" => "UnitPriceSpecification",
        "price" => plan.price_cents / 100,
        "priceCurrency" => "USD",
        "billingDuration" => plan.duration_days || 30,
        "unitCode" => "DAY"
      }
    }
  end

  defp absolute_url(path), do: MemePingWeb.Endpoint.url() <> path
end
