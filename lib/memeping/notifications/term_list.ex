defmodule MemePing.Notifications.TermList do
  use Ecto.Schema
  import Ecto.Changeset

  alias MemePing.Accounts.User
  alias MemePing.Notifications.Notifier

  @type t :: %__MODULE__{}

  schema "term_lists" do
    field :name, :string
    field :terms, :string
    belongs_to :user, User
    has_many :notifiers, Notifier, foreign_key: :term_list_id

    timestamps()
  end

  @doc """
  Whether any term in `term_list` (case-insensitive regex, one per line)
  matches `value`. Used to exclude a token by name/ticker.
  """
  @spec match?(t() | nil, String.t() | nil) :: boolean()
  def match?(term_list, value)

  def match?(%__MODULE__{terms: terms}, value) when is_binary(terms) and is_binary(value) do
    terms
    |> String.split("\n", trim: true)
    |> Enum.any?(fn term ->
      case Regex.compile(term, "i") do
        {:ok, regex} -> Regex.match?(regex, value)
        {:error, _reason} -> false
      end
    end)
  end

  def match?(_term_list, _value), do: false

  @doc false
  def changeset(term_list, attrs) do
    term_list
    |> cast(attrs, [:name, :terms, :user_id])
    |> update_change(:terms, &normalize_terms/1)
    |> validate_required([:name, :terms, :user_id])
    |> validate_length(:name, max: 50)
    |> unique_constraint(:name, name: :term_lists_user_id_name_index)
    |> validate_terms()
  end

  defp normalize_terms(terms) do
    terms
    |> String.split(~r/\R/u)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.join("\n")
  end

  @max_term_length 100
  @max_term_count 2000

  defp validate_terms(changeset) do
    case get_change(changeset, :terms) || get_field(changeset, :terms) do
      nil ->
        changeset

      terms ->
        lines = String.split(terms, "\n", trim: true)

        changeset
        |> validate_term_count(lines)
        |> then(&Enum.reduce(lines, &1, fn term, acc -> validate_term(acc, term) end))
    end
  end

  defp validate_term_count(changeset, lines) when length(lines) > @max_term_count do
    add_error(changeset, :terms, "must not contain more than #{@max_term_count} expressions")
  end

  defp validate_term_count(changeset, _lines), do: changeset

  defp validate_term(changeset, term) do
    if String.length(term) > @max_term_length do
      add_error(
        changeset,
        :terms,
        "contains an expression longer than #{@max_term_length} characters: #{term}"
      )
    else
      case Regex.compile(term, "i") do
        {:ok, _regex} -> changeset
        {:error, _reason} -> add_error(changeset, :terms, "contains an invalid regex: #{term}")
      end
    end
  end
end
