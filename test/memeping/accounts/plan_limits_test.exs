defmodule MemePing.Accounts.PlanLimitsTest do
  use MemePing.DataCase

  alias MemePing.Accounts
  alias MemePing.Accounts.User
  alias MemePing.Notifications
  alias MemePing.Notifications.TermLists
  alias MemePing.Telegram

  test "exposes the configured limits for each plan" do
    free_user = Repo.insert!(User.changeset(%User{}, %{}))
    basic_user = Repo.insert!(User.plan_changeset(%User{}, %{plan: "basic"}))
    max_user = Repo.insert!(User.plan_changeset(%User{}, %{plan: "max"}))

    assert Accounts.resource_limit(free_user, :notifier) == 1
    assert Accounts.resource_limit(basic_user, :telegram_channel) == 3
    assert Accounts.resource_limit(max_user, :notifier) == 30
    assert Accounts.resource_limit(max_user, :term_list) == nil
  end

  test "rejects creating resources beyond the user's plan limits" do
    user = Repo.insert!(User.changeset(%User{}, %{}))

    assert {:ok, _} = Notifications.create_notifier(user, %{"name" => "One", "chain" => "solana"})

    assert {:error, notifier_changeset} =
             Notifications.create_notifier(user, %{"name" => "Two", "chain" => "solana"})

    assert {"Your plan allows up to 1 notifiers.", _} =
             Keyword.fetch!(notifier_changeset.errors, :name)

    assert {:ok, _} = Telegram.create_channel(user, %{"name" => "One", "chat_id" => "-1001"})

    assert {:error, channel_changeset} =
             Telegram.create_channel(user, %{"name" => "Two", "chat_id" => "-1002"})

    assert {"Your plan allows up to 1 Telegram channels.", _} =
             Keyword.fetch!(channel_changeset.errors, :name)

    assert {:error, term_list_changeset} =
             TermLists.create_term_list(user, %{"name" => "Blocked", "terms" => "spam"})

    assert {"Your plan allows up to 0 forbidden term lists.", _} =
             Keyword.fetch!(term_list_changeset.errors, :name)
  end
end
