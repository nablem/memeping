defmodule MemePing.Notifications.ManagerTest do
  use MemePing.DataCase

  alias MemePing.Accounts.User
  alias MemePing.Notifications
  alias MemePing.Notifications.Manager
  alias MemePing.Telegram

  setup do
    start_supervised!({Registry, keys: :unique, name: MemePing.Notifications.Registry})

    start_supervised!(
      {DynamicSupervisor, strategy: :one_for_one, name: MemePing.Notifications.DynamicSupervisor}
    )

    user = Repo.insert!(User.changeset(%User{}, %{}))
    {:ok, channel} = Telegram.create_channel(user, %{"name" => "Main", "chat_id" => "-100123"})

    %{user: user, channel: channel}
  end

  defp worker_pid(id) do
    case Registry.lookup(MemePing.Notifications.Registry, id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  test "starts a worker at boot for each enabled, channel-linked notifier", %{
    user: user,
    channel: channel
  } do
    {:ok, notifier} =
      Notifications.create_notifier(user, %{
        "name" => "Solana calls",
        "chain" => "solana",
        "telegram_channel_id" => channel.id
      })

    start_supervised!(Manager)

    assert is_pid(worker_pid(notifier.id))
  end

  test "does not start a worker for a notifier with no Telegram channel", %{user: user} do
    {:ok, notifier} =
      Notifications.create_notifier(user, %{"name" => "No channel", "chain" => "solana"})

    start_supervised!(Manager)

    assert worker_pid(notifier.id) == nil
  end

  test "starts a worker immediately when a notifier is created after boot", %{
    user: user,
    channel: channel
  } do
    start_supervised!(Manager)

    {:ok, notifier} =
      Notifications.create_notifier(user, %{
        "name" => "Ethereum calls",
        "chain" => "ethereum",
        "telegram_channel_id" => channel.id
      })

    assert is_pid(worker_pid(notifier.id))
  end

  test "stops the worker when a notifier is disabled, restarts it when re-enabled", %{
    user: user,
    channel: channel
  } do
    {:ok, notifier} =
      Notifications.create_notifier(user, %{
        "name" => "Toggle me",
        "chain" => "base",
        "telegram_channel_id" => channel.id
      })

    start_supervised!(Manager)
    assert pid = worker_pid(notifier.id)
    ref = Process.monitor(pid)

    {:ok, notifier} = Notifications.update_notifier(notifier, %{"enabled" => "false"})
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    refute Process.alive?(pid)

    {:ok, notifier} = Notifications.update_notifier(notifier, %{"enabled" => "true"})
    assert is_pid(worker_pid(notifier.id))
  end

  test "stops the worker when a notifier is deleted", %{user: user, channel: channel} do
    {:ok, notifier} =
      Notifications.create_notifier(user, %{
        "name" => "Delete me",
        "chain" => "bsc",
        "telegram_channel_id" => channel.id
      })

    start_supervised!(Manager)
    assert pid = worker_pid(notifier.id)
    ref = Process.monitor(pid)

    {:ok, _notifier} = Notifications.delete_notifier(notifier)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    refute Process.alive?(pid)
  end
end
