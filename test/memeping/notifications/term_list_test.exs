defmodule MemePing.Notifications.TermListTest do
  use ExUnit.Case, async: true

  alias MemePing.Notifications.TermList

  test "returns false when the term list is nil" do
    refute TermList.match?(nil, "SpamCoin")
  end

  test "matches case-insensitively against any line" do
    term_list = %TermList{terms: "airdrop\nrugpull"}
    assert TermList.match?(term_list, "Big AIRDROP Token")
    assert TermList.match?(term_list, "rugpull coin")
    refute TermList.match?(term_list, "Legit Coin")
  end

  test "supports regex terms" do
    term_list = %TermList{terms: "^\\$?doge"}
    assert TermList.match?(term_list, "$DOGE")
    refute TermList.match?(term_list, "PepeDoge")
  end

  test "returns false for a nil value" do
    term_list = %TermList{terms: "spam"}
    refute TermList.match?(term_list, nil)
  end

  test "changeset strips blank lines and '#' comment lines from terms" do
    changeset =
      TermList.changeset(%TermList{}, %{
        "name" => "Spam",
        "user_id" => 1,
        "terms" => "# Section header\n\nairdrop\n  # another comment\nrugpull\n"
      })

    assert Ecto.Changeset.get_change(changeset, :terms) == "airdrop\nrugpull"
  end
end
