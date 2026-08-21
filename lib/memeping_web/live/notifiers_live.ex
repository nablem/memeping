defmodule MemePingWeb.NotifiersLive do
  use MemePingWeb, :live_view

  alias MemePing.Notifications
  alias MemePing.Notifications.Notifier
  alias MemePing.Notifications.TermLists
  alias MemePing.Telegram

  def render(%{live_action: :index} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_tab={:notifiers}>
      <div class="flex items-center justify-between gap-4 mb-8">
        <div class="space-y-2">
          <h1 class="text-2xl font-semibold">Notifiers</h1>
          
          <ul class="list-disc list-inside space-y-1 text-sm font-semibold text-primary">
            <li>Set up the rules for the memecoin calls you want to receive from DEX Screener.</li>
            
            <li>Choose the chain, Telegram destination, forbidden terms, and metric thresholds.</li>
          </ul>
        </div>
         <.link navigate={~p"/notifiers/new"} class="btn btn-primary btn-sm">New notifier</.link>
      </div>
      
      <p :if={@notifiers == []} class="opacity-70 mt-2">
        No notifiers yet. Create one to start receiving calls on Telegram.
      </p>
      
      <table :if={@notifiers != []} class="table">
        <thead>
          <tr>
            <th>Name</th>
            
            <th>Chain</th>
            
            <th>Telegram channel</th>
            
            <th>Term list</th>
            
            <th>Status</th>
            
            <th></th>
          </tr>
        </thead>
        
        <tbody>
          <tr :for={notifier <- @notifiers}>
            <td>{notifier.name}</td>
            
            <td>{notifier.chain}</td>
            
            <td>{channel_name(notifier)}</td>
            
            <td>{term_list_name(notifier)}</td>
            
            <td>
              <span class={[
                "badge",
                notifier.enabled && "badge-accent text-white",
                !notifier.enabled && "badge-ghost"
              ]}>
                {if notifier.enabled, do: "enabled", else: "disabled"}
              </span>
            </td>
            
            <td class="flex gap-2 justify-end">
              <.link navigate={~p"/notifiers/#{notifier}/edit"} class="btn btn-ghost btn-xs">
                Edit
              </.link>
              <.link
                phx-click={JS.push("delete", value: %{id: notifier.id})}
                data-confirm={"Delete notifier \"#{notifier.name}\"?"}
                class="btn btn-ghost btn-xs text-error"
              >
                Delete
              </.link>
            </td>
          </tr>
        </tbody>
      </table>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_tab={:notifiers}>
      <h1 class="text-2xl font-semibold mb-8">
        {if @live_action == :new, do: "New notifier", else: "Edit notifier"}
      </h1>
      
      <.form for={@form} id="notifier-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <.input
            field={@form[:name]}
            type="text"
            label="Name"
            placeholder="e.g. New Solana pairs"
            maxlength="25"
          /> <.input field={@form[:chain]} type="select" label="Chain" options={Notifier.chains()} />
          <.input
            field={@form[:telegram_channel_id]}
            type="select"
            label="Telegram channel"
            options={channel_options(@telegram_channels)}
          />
          <.input
            field={@form[:term_list_id]}
            type="select"
            label="Forbidden term list"
            options={term_list_options(@term_lists)}
          /> <.input field={@form[:enabled]} type="checkbox" label="Enabled" />
        </div>
        
        <div>
          <h2 class="text-lg font-semibold mb-2">Match criteria</h2>
          
          <p class="text-sm mb-3">
            <strong class="text-primary">
              Leave both min and max blank for metrics this notifier does not depend on.
              A single value sets only that lower or upper bound.
            </strong>
          </p>
          
          <.inputs_for :let={cf} field={@form[:criteria]}>
            <table class="table">
              <thead>
                <tr>
                  <th>Metric</th>
                  
                  <th>Min</th>
                  
                  <th>Max</th>
                </tr>
              </thead>
              
              <tbody>
                <tr :for={{metric, label} <- Notifications.metrics()}>
                  <td>{label}</td>
                  
                  <td><.input field={cf[:"#{metric}_min"]} type="number" step="1" /></td>
                  
                  <td><.input field={cf[:"#{metric}_max"]} type="number" step="1" /></td>
                </tr>
              </tbody>
            </table>
          </.inputs_for>
        </div>
        
        <div class="flex gap-2">
          <.button type="submit" phx-disable-with="Saving...">Save notifier</.button>
          <.link navigate={~p"/notifiers"} class="btn btn-ghost">Cancel</.link>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:notifiers, Notifications.list_notifiers(socket.assigns.current_user))
     |> assign(:telegram_channels, Telegram.list_channels(socket.assigns.current_user))
     |> assign(:term_lists, TermLists.list_term_lists(socket.assigns.current_user))}
  end

  defp channel_options(channels),
    do: [{"— none linked yet —", nil} | Enum.map(channels, &{&1.name, &1.id})]

  defp channel_name(%{telegram_channel_record: %{name: name}}), do: name
  defp channel_name(_notifier), do: "—"

  defp term_list_options(term_lists),
    do: [{"— none linked yet —", nil} | Enum.map(term_lists, &{&1.name, &1.id})]

  defp term_list_name(%{term_list: %{name: name}}), do: name
  defp term_list_name(_notifier), do: "—"

  def handle_params(%{"id" => id}, _uri, %{assigns: %{live_action: :edit}} = socket) do
    notifier = Notifications.get_notifier!(socket.assigns.current_user, id)

    {:noreply,
     socket
     |> assign(:notifier, notifier)
     |> assign(:form, to_form(Notifications.change_notifier(notifier)))}
  end

  def handle_params(_params, _uri, %{assigns: %{live_action: :new}} = socket) do
    notifier = Notifications.new_notifier()

    {:noreply,
     socket
     |> assign(:notifier, notifier)
     |> assign(:form, to_form(Notifications.change_notifier(notifier)))}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  def handle_event("validate", %{"notifier" => params}, socket) do
    form =
      socket.assigns.notifier
      |> Notifications.change_notifier(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"notifier" => params}, socket) do
    save_notifier(socket, socket.assigns.live_action, params)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    notifier = Notifications.get_notifier!(socket.assigns.current_user, id)
    {:ok, _} = Notifications.delete_notifier(notifier)

    {:noreply,
     assign(socket, :notifiers, Notifications.list_notifiers(socket.assigns.current_user))}
  end

  defp save_notifier(socket, :new, params) do
    case Notifications.create_notifier(socket.assigns.current_user, params) do
      {:ok, _notifier} ->
        {:noreply, push_navigate(socket, to: ~p"/notifiers")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_notifier(socket, :edit, params) do
    case Notifications.update_notifier(socket.assigns.notifier, params) do
      {:ok, _notifier} ->
        {:noreply, push_navigate(socket, to: ~p"/notifiers")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end
end
