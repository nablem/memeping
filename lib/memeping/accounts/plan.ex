defmodule MemePing.Accounts.Plan do
  @moduledoc """
  Static definitions of the subscription plans users can choose from.

  Payment processing is not implemented yet; users can switch plans freely
  for now. `nil` limits mean unlimited.
  """

  @type t :: %{
          id: String.t(),
          name: String.t(),
          price_cents: non_neg_integer(),
          duration_days: pos_integer() | nil,
          notifier_limit: pos_integer() | nil,
          telegram_channel_limit: pos_integer() | nil,
          term_list_limit: pos_integer() | nil
        }

  @plans [
    %{
      id: "free",
      name: "Free",
      price_cents: 0,
      duration_days: nil,
      notifier_limit: 1,
      telegram_channel_limit: 1,
      term_list_limit: 0
    },
    %{
      id: "basic",
      name: "Basic",
      price_cents: 1900,
      duration_days: 30,
      notifier_limit: 3,
      telegram_channel_limit: 3,
      term_list_limit: 1
    },
    %{
      id: "max",
      name: "Max",
      price_cents: 3900,
      duration_days: 30,
      notifier_limit: nil,
      telegram_channel_limit: nil,
      term_list_limit: nil
    }
  ]

  @spec all() :: [t()]
  def all, do: @plans

  @spec ids() :: [String.t()]
  def ids, do: Enum.map(@plans, & &1.id)

  @spec get!(String.t()) :: t()
  def get!(id), do: Enum.find(@plans, &(&1.id == id)) || raise("unknown plan #{id}")
end
