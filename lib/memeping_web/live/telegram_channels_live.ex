defmodule MemePingWeb.TelegramChannelsLive do
  use MemePingWeb, :live_view

  alias MemePing.Telegram

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_tab={:telegram_channels}>
      <div class="flex items-center justify-between gap-4 mb-8">
        <div class="space-y-2">
          <h1 class="text-2xl font-semibold">Telegram channels</h1>

          <ul class="list-disc list-inside space-y-1 text-sm font-semibold text-primary">
            <li>Create a Telegram channel, then add its name and chat ID here.</li>
            <li>Add <strong>@memeping_bot</strong> as an admin with permission to post messages.</li>
            <li>Link the channel to one or more notifiers to route matching calls there.</li>
          </ul>
        </div>
        <button phx-click="new" class="btn btn-primary btn-sm">Add channel</button>
      </div>

      <div :if={@show_form} class="border border-base-300 p-5 mb-8">
        <h2 class="text-lg font-semibold mb-4">
          {if @editing, do: "Edit channel", else: "Add channel"}
        </h2>

        <.form
          for={@form}
          id="telegram-channel-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <.input
            field={@form[:name]}
            type="text"
            label="Channel name"
            placeholder="e.g. Main calls"
            maxlength="50"
          />
          <.input
            field={@form[:chat_id]}
            type="text"
            label="Telegram chat ID"
            placeholder="e.g. -1001234567890"
            maxlength="100"
          />
          <p class="text-sm opacity-70">
            Telegram connectivity and test messages will be added later.
          </p>

          <div class="flex gap-2">
            <.button type="submit" phx-disable-with="Saving...">Save channel</.button>
            <button type="button" phx-click="cancel" class="btn btn-ghost">Cancel</button>
          </div>
        </.form>
      </div>

      <p :if={@channels == []} class="opacity-70 mt-2">No Telegram channels saved yet.</p>

      <div :if={@channels != []} id="telegram-channels" class="grid gap-3 sm:grid-cols-2">
        <article
          :for={channel <- @channels}
          id={"telegram-channel-#{channel.id}"}
          class="border border-base-300 p-4"
        >
          <h2 class="font-semibold">{channel.name}</h2>

          <p class="font-mono text-sm opacity-70 mt-1">{channel.chat_id}</p>

          <div class="flex gap-2 mt-4">
            <button
              id={"test-telegram-channel-#{channel.id}"}
              phx-click="test"
              phx-value-id={channel.id}
              class="btn btn-secondary btn-xs"
            >
              Test message
            </button>
            <button phx-click="edit" phx-value-id={channel.id} class="btn btn-ghost btn-xs">
              Edit
            </button>
            <button
              phx-click="delete"
              phx-value-id={channel.id}
              data-confirm={"Delete channel \"#{channel.name}\"?"}
              class="btn btn-ghost btn-xs text-error"
            >
              Delete
            </button>
          </div>
        </article>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket),
    do: {:ok, load_channels(socket) |> assign(:show_form, false)}

  def handle_event("new", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing, nil)
     |> assign(:form, to_form(Telegram.change_channel(Telegram.new_channel())))
     |> assign(:show_form, true)}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    channel = Telegram.get_channel!(socket.assigns.current_user, id)

    {:noreply,
     socket
     |> assign(:editing, channel)
     |> assign(:form, to_form(Telegram.change_channel(channel)))
     |> assign(:show_form, true)}
  end

  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, :show_form, false)}

  def handle_event("validate", %{"channel" => params}, socket) do
    channel = socket.assigns.editing || Telegram.new_channel()

    form =
      channel
      |> Telegram.change_channel(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"channel" => params}, socket) do
    result =
      case socket.assigns.editing do
        nil -> Telegram.create_channel(socket.assigns.current_user, params)
        channel -> Telegram.update_channel(channel, params)
      end

    case result do
      {:ok, _channel} ->
        {:noreply,
         socket
         |> load_channels()
         |> assign(:show_form, false)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    socket.assigns.current_user
    |> Telegram.get_channel!(id)
    |> Telegram.delete_channel()

    {:noreply, load_channels(socket)}
  end

  def handle_event("test", %{"id" => id}, socket) do
    channel = Telegram.get_channel!(socket.assigns.current_user, id)

    case Telegram.send_test_message(channel) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Test message sent to #{channel.name}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, telegram_error_message(reason))}
    end
  end

  defp telegram_error_message(:missing_telegram_bot_token),
    do: "Telegram bot token is not configured."

  defp telegram_error_message({:telegram_api, description}),
    do: "Telegram rejected the message: #{description}"

  defp telegram_error_message(_reason),
    do: "The test message could not be sent. Check the chat ID and bot permissions."

  defp load_channels(socket) do
    assign(socket, :channels, Telegram.list_channels(socket.assigns.current_user))
  end
end
