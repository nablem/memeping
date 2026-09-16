defmodule MemePing.Notifications.Criteria do
  @moduledoc """
  Min/max thresholds a token must fall within to trigger a notifier.

  Mirrors the metric set used by the `bentley` prototype's notifier engine
  (see `components/lib/bentley/notifiers/definition.ex`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @metrics [
    {:age_hours, "Pair age (hours)"},
    {:market_cap, "Market cap ($)"},
    {:liquidity, "Liquidity ($)"},
    {:volume_1h, "Volume 1h ($)"},
    {:volume_6h, "Volume 6h ($)"},
    {:volume_24h, "Volume 24h ($)"},
    {:change_5m, "Price change 5m (%)"},
    {:change_1h, "Price change 1h (%)"},
    {:change_6h, "Price change 6h (%)"},
    {:change_24h, "Price change 24h (%)"},
    {:boost, "Boost"},
    {:ath, "All-time high ($)"}
  ]

  @primary_key false
  embedded_schema do
    for {metric, _label} <- @metrics do
      field :"#{metric}_min", :float
      field :"#{metric}_max", :float
    end
  end

  @spec metrics() :: [{atom(), String.t()}]
  def metrics, do: @metrics

  @doc """
  Whether `token`'s current metrics fall within every range set on `criteria`.

  Unset (`nil`) min/max bounds are unconstrained; a metric with no matching
  token value (`nil`) always fails. Ported from
  `Bentley.Notifiers.Criteria.match?/3`.
  """
  @spec match?(struct() | map(), t(), NaiveDateTime.t()) :: boolean()
  def match?(token, %__MODULE__{} = criteria, now \\ current_time()) do
    Enum.all?(@metrics, fn {metric, _label} ->
      min = Map.get(criteria, :"#{metric}_min")
      max = Map.get(criteria, :"#{metric}_max")

      if is_nil(min) and is_nil(max) do
        true
      else
        token
        |> metric_value(metric, now)
        |> within_range?(min, max)
      end
    end)
  end

  @spec age_in_hours(struct() | map(), NaiveDateTime.t()) :: float() | nil
  def age_in_hours(token, now \\ current_time()) do
    case Map.get(token, :created_on_chain_at) do
      %NaiveDateTime{} = created_on_chain_at ->
        NaiveDateTime.diff(now, created_on_chain_at, :second) / 3_600

      _ ->
        nil
    end
  end

  defp metric_value(token, :age_hours, now), do: age_in_hours(token, now)
  defp metric_value(token, :boost, _now), do: Map.get(token, :boost) || 0
  defp metric_value(token, metric, _now), do: Map.get(token, metric)

  defp within_range?(nil, _min, _max), do: false

  defp within_range?(value, min, max) when is_number(value) do
    (is_nil(min) or value >= min) and (is_nil(max) or value <= max)
  end

  defp within_range?(_value, _min, _max), do: false

  defp current_time, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

  @doc false
  def changeset(criteria, attrs) do
    fields =
      Enum.flat_map(@metrics, fn {metric, _label} -> [:"#{metric}_min", :"#{metric}_max"] end)

    criteria
    |> cast(attrs, fields)
    |> validate_ranges(fields)
  end

  defp validate_ranges(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, changeset ->
      if String.ends_with?(to_string(field), "_min") do
        max_field =
          field
          |> to_string()
          |> String.replace_suffix("_min", "_max")
          |> String.to_existing_atom()

        validate_min_max(changeset, field, max_field)
      else
        changeset
      end
    end)
  end

  defp validate_min_max(changeset, min_field, max_field) do
    min = get_field(changeset, min_field)
    max = get_field(changeset, max_field)

    if is_number(min) and is_number(max) and min > max do
      add_error(changeset, min_field, "must be less than or equal to max")
    else
      changeset
    end
  end
end
