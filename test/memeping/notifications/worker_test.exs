defmodule MemePing.Notifications.WorkerTest do
  use MemePing.DataCase

  alias MemePing.Accounts.User
  alias MemePing.Discovery.Token
  alias MemePing.Notifications
  alias MemePing.Notifications.NotificationDelivery
  alias MemePing.Notifications.TermLists
  alias MemePing.Notifications.Worker
  alias MemePing.Telegram

  setup do
    previous_client = Application.get_env(:memeping, :telegram_client)
    Application.put_env(:memeping, :telegram_client, MemePing.Telegram.TestClient)
    Application.put_env(:memeping, :telegram_test_result, :ok)

    on_exit(fn ->
      Application.put_env(:memeping, :telegram_client, previous_client)
      Application.delete_env(:memeping, :telegram_test_result)
    end)

    user = Repo.insert!(User.changeset(%User{}, %{}))
    {:ok, channel} = Telegram.create_channel(user, %{"name" => "Main", "chat_id" => "-100123"})

    {:ok, notifier} =
      Notifications.create_notifier(user, %{"name" => "Solana calls", "chain" => "solana"})

    notifier = %{notifier | telegram_channel_record: channel}

    %{user: user, channel: channel, notifier: notifier}
  end

  defp insert_token!(attrs) do
    %Token{}
    |> Token.changeset(
      Map.merge(
        %{
          active: true,
          chain_id: "solana",
          last_checked_at: ~N[2026-09-02 10:00:00],
          created_on_chain_at: ~N[2026-09-01 10:00:00],
          name: "Doge Killer",
          ticker: "DOGEK",
          market_cap: 50_000.0
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  describe "matching_tokens/2" do
    test "returns tokens on the notifier's chain that satisfy its criteria", %{notifier: notifier} do
      token = insert_token!(%{token_address: "AddrA"})
      insert_token!(%{token_address: "AddrB", chain_id: "ethereum"})

      assert [matched] = Worker.matching_tokens(notifier)
      assert matched.token_address == token.token_address
    end

    test "excludes tokens not yet checked by the Updater", %{notifier: notifier} do
      insert_token!(%{token_address: "AddrC", last_checked_at: nil})
      assert Worker.matching_tokens(notifier) == []
    end

    test "excludes inactive tokens", %{notifier: notifier} do
      insert_token!(%{token_address: "AddrD", active: false})
      assert Worker.matching_tokens(notifier) == []
    end

    test "excludes tokens outside the criteria range", %{user: user, channel: channel} do
      {:ok, notifier} =
        Notifications.create_notifier(user, %{
          "name" => "Big caps",
          "chain" => "solana",
          "criteria" => %{"market_cap_min" => "1000000"}
        })

      notifier = %{notifier | telegram_channel_record: channel}
      insert_token!(%{token_address: "AddrE", market_cap: 1_000.0})

      assert Worker.matching_tokens(notifier) == []
    end

    test "excludes tokens flagged by the notifier's forbidden-terms list", %{
      user: user,
      channel: channel
    } do
      {:ok, term_list} =
        TermLists.create_term_list(user, %{"name" => "Spam", "terms" => "killer"})

      {:ok, notifier} =
        Notifications.create_notifier(user, %{
          "name" => "Filtered",
          "chain" => "solana",
          "term_list_id" => term_list.id
        })

      notifier = %{notifier | telegram_channel_record: channel, term_list: term_list}
      insert_token!(%{token_address: "AddrF"})

      assert Worker.matching_tokens(notifier) == []
    end

    test "excludes tokens already delivered to this notifier", %{notifier: notifier} do
      insert_token!(%{token_address: "AddrG"})

      Repo.insert!(
        NotificationDelivery.changeset(%NotificationDelivery{}, %{
          notifier_id: notifier.id,
          chain_id: "solana",
          token_address: "AddrG",
          telegram_channel: "-100123",
          message_text: "already sent",
          sent_at: ~N[2026-09-02 09:00:00]
        })
      )

      assert Worker.matching_tokens(notifier) == []
    end
  end

  describe "deliver_notifications/2" do
    test "sends a matching token and records the delivery", %{notifier: notifier} do
      insert_token!(%{token_address: "AddrH"})

      assert {:ok, %{matched: 1, sent: 1, failed: 0}} = Worker.deliver_notifications(notifier)

      assert Repo.get_by(NotificationDelivery, notifier_id: notifier.id, token_address: "AddrH")
    end

    test "never resends a token already delivered", %{notifier: notifier} do
      insert_token!(%{token_address: "AddrI"})

      assert {:ok, %{sent: 1}} = Worker.deliver_notifications(notifier)
      assert {:ok, %{matched: 0, sent: 0}} = Worker.deliver_notifications(notifier)
      assert Repo.aggregate(NotificationDelivery, :count) == 1
    end

    test "counts a Telegram failure without recording a delivery", %{notifier: notifier} do
      Application.put_env(:memeping, :telegram_test_result, {:error, :boom})
      insert_token!(%{token_address: "AddrJ"})

      assert {:ok, %{matched: 1, sent: 0, failed: 1}} = Worker.deliver_notifications(notifier)
      refute Repo.get_by(NotificationDelivery, token_address: "AddrJ")
    end

    test "skips delivery entirely when the notifier has no Telegram channel", %{
      notifier: notifier
    } do
      notifier = %{notifier | telegram_channel_record: nil}
      insert_token!(%{token_address: "AddrK"})

      assert {:ok, %{matched: 0, sent: 0, failed: 0}} = Worker.deliver_notifications(notifier)
    end
  end
end
