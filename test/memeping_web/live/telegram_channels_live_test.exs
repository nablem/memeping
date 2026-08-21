defmodule MemePingWeb.TelegramChannelsLiveTest do
  use MemePingWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MemePing.Accounts.User
  alias MemePing.Repo
  alias MemePing.Telegram

  setup %{conn: conn} do
    user = Repo.insert!(User.changeset(%User{}, %{}))
    conn = Plug.Test.init_test_session(conn, %{"user_id" => user.id})
    %{conn: conn, user: user}
  end

  test "creates, edits and deletes a Telegram channel inline", %{conn: conn, user: user} do
    {:ok, live_view, html} = live(conn, ~p"/telegram-channels")
    assert html =~ "No Telegram channels saved yet"

    live_view
    |> element("button", "Add channel")
    |> render_click()

    live_view
    |> form("#telegram-channel-form",
      channel: %{"name" => "Main calls", "chat_id" => "-1001234567890"}
    )
    |> render_submit()

    assert html = render(live_view)
    assert html =~ "Main calls"
    assert html =~ "-1001234567890"

    [channel] = Telegram.list_channels(user)

    live_view
    |> element("button", "Edit")
    |> render_click()

    live_view
    |> form("#telegram-channel-form", channel: %{"name" => "VIP calls"})
    |> render_submit()

    assert render(live_view) =~ "VIP calls"

    live_view
    |> element("button", "Delete")
    |> render_click()

    refute has_element?(live_view, "#telegram-channel-#{channel.id}")
    assert render(live_view) =~ "No Telegram channels saved yet"
  end

  test "rejects duplicate channel names and chat IDs for the same user", %{conn: conn} do
    {:ok, live_view, _html} = live(conn, ~p"/telegram-channels")

    live_view
    |> element("button", "Add channel")
    |> render_click()

    live_view
    |> form("#telegram-channel-form",
      channel: %{"name" => "Main calls", "chat_id" => "-1001234567890"}
    )
    |> render_submit()

    live_view
    |> element("button", "Add channel")
    |> render_click()

    live_view
    |> form("#telegram-channel-form",
      channel: %{"name" => "Main calls", "chat_id" => "-1009876543210"}
    )
    |> render_submit()

    assert has_element?(
             live_view,
             "#telegram-channel-form p.text-error",
             "has already been taken"
           )
  end

  test "sends a test message through the configured Telegram client", %{conn: conn} do
    previous_client = Application.get_env(:memeping, :telegram_client)
    Application.put_env(:memeping, :telegram_client, MemePing.Telegram.TestClient)

    on_exit(fn ->
      Application.put_env(:memeping, :telegram_client, previous_client)
    end)

    {:ok, live_view, _html} = live(conn, ~p"/telegram-channels")

    live_view
    |> element("button", "Add channel")
    |> render_click()

    live_view
    |> form("#telegram-channel-form",
      channel: %{"name" => "Main calls", "chat_id" => "-1001234567890"}
    )
    |> render_submit()

    live_view
    |> element("button", "Test message")
    |> render_click()

    assert render(live_view) =~ "Test message sent to Main calls"
  end
end
