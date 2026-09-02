defmodule MemePing.Discovery.UpdaterTest do
  use MemePing.DataCase

  alias MemePing.Accounts.User
  alias MemePing.Discovery.Token
  alias MemePing.Discovery.Updater
  alias MemePing.Notifications

  defp insert_token!(attrs) do
    %Token{}
    |> Token.changeset(Map.merge(%{active: true}, attrs))
    |> Repo.insert!()
  end

  defp create_user! do
    Repo.insert!(User.changeset(%User{}, %{}))
  end

  defp create_notifier!(user, chain, enabled \\ true) do
    {:ok, notifier} =
      Notifications.create_notifier(user, %{
        "name" => "#{chain}-#{System.unique_integer([:positive])}",
        "chain" => chain
      })

    if enabled do
      notifier
    else
      {:ok, notifier} = Notifications.update_notifier(notifier, %{"enabled" => false})
      notifier
    end
  end

  describe "due_tokens/2" do
    test "returns nothing when no notifier is enabled for any chain" do
      insert_token!(%{chain_id: "solana", token_address: "AddrA"})

      assert Updater.due_tokens() == []
    end

    test "only considers chains with at least one enabled notifier" do
      user = create_user!()
      create_notifier!(user, "solana")

      insert_token!(%{chain_id: "solana", token_address: "AddrA"})
      insert_token!(%{chain_id: "ethereum", token_address: "AddrB"})

      due = Updater.due_tokens()

      assert Enum.map(due, & &1.chain_id) == ["solana"]
    end

    test "ignores chains whose only notifier is disabled" do
      user = create_user!()
      create_notifier!(user, "ethereum", false)

      insert_token!(%{chain_id: "ethereum", token_address: "AddrC"})

      assert Updater.due_tokens() == []
    end

    test "does not return inactive tokens even on a covered chain" do
      user = create_user!()
      create_notifier!(user, "solana")

      insert_token!(%{chain_id: "solana", token_address: "AddrD", active: false})

      assert Updater.due_tokens() == []
    end
  end
end
