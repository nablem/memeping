defmodule MemePingWeb.TermListsLive do
  use MemePingWeb, :live_view

  alias MemePing.Notifications.TermLists

  @terms_placeholder ~S"""
  ^elon.*musk$
  presale|airdrop|giveaway
  rug\s*pull
  \bscam\b
  pepe.*moon
  ^test\d+
  inu$
  ^x{3,}
  ^\d+$
  v[2-9]
  """

  def render(%{live_action: :index} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_tab={:term_lists}>
      <div class="flex items-center justify-between gap-4 mb-8">
        <div class="space-y-2">
          <h1 class="text-2xl font-semibold">Lists of forbidden terms</h1>

          <ul class="list-disc list-inside space-y-1 text-sm font-semibold text-primary">
            <li>
              Link a list to a notifier to exclude memecoins whose names match any of its case-insensitive regex patterns.
            </li>

            <li>Matching is applied to the name only, not the ticker or description.</li>
          </ul>
        </div>
        <.link navigate={~p"/term-lists/new"} class="btn btn-primary btn-sm">New term list</.link>
      </div>

      <p :if={@term_lists == []} class="opacity-70 mt-2">No forbidden term lists yet.</p>

      <div :if={@term_lists != []} class="grid gap-3 sm:grid-cols-2">
        <article
          :for={term_list <- @term_lists}
          id={"term-list-#{term_list.id}"}
          class="border border-base-300 p-4"
        >
          <div class="flex items-start justify-between gap-3">
            <div>
              <h2 class="font-semibold">{term_list.name}</h2>

              <p class="text-sm opacity-70">{term_count(term_list.terms)} regexes</p>
            </div>
          </div>
          <pre class="mt-3 p-3 bg-base-200 text-sm overflow-x-auto">{preview_terms(term_list.terms)}</pre>
          <div class="flex gap-2 mt-4">
            <.link navigate={~p"/term-lists/#{term_list}/edit"} class="btn btn-ghost btn-xs">
              Edit
            </.link>
            <button
              phx-click="delete"
              phx-value-id={term_list.id}
              data-confirm={"Delete term list \"#{term_list.name}\"?"}
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

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_tab={:term_lists}>
      <h1 class="text-2xl font-semibold mb-2">
        {if @live_action == :new, do: "New forbidden term list", else: "Edit forbidden term list"}
      </h1>

      <p class="text-sm opacity-70 mb-8">
        Enter one regular expression per line. Matching is case-insensitive and checks token names and tickers.
      </p>

      <.form for={@form} id="term-list-form" phx-change="validate" phx-submit="save" class="space-y-5">
        <.input
          field={@form[:name]}
          type="text"
          label="List name"
          placeholder="e.g. Promotional terms"
          maxlength="50"
        />
        <.input
          field={@form[:terms]}
          type="textarea"
          label="Forbidden regexes"
          placeholder={terms_placeholder()}
          rows="12"
        />
        <div class="flex gap-2">
          <.button type="submit" phx-disable-with="Saving...">Save term list</.button>
          <.link navigate={~p"/term-lists"} class="btn btn-ghost">Cancel</.link>
        </div>
      </.form>

      <section aria-labelledby="forbidden-term-examples" class="border-t border-base-300 pt-5">
        <h2 id="forbidden-term-examples" class="text-sm font-semibold">Examples</h2>
        <ul phx-no-curly-interpolation class="mt-2 space-y-1 text-sm text-base-content/70">
          <li>Exclude a name or ticker containing "scam" anywhere: <code>scam</code></li>
          <li>Exclude "scam" as a complete word in the middle of a name: <code>\bscam\b</code></li>
          <li>Exclude a name or ticker starting with "elon": <code>^elon</code></li>
          <li>Exclude a name or ticker ending with "inu": <code>inu$</code></li>
          <li>Exclude the exact name or ticker "test coin": <code>^test coin$</code></li>
          <li>
            Exclude names containing "presale", "airdrop", or "giveaway":
            <code>presale|airdrop|giveaway</code>
          </li>
          <li>Exclude names containing "rug pull" with optional spaces: <code>rug\s*pull</code></li>
          <li>Exclude names where "pepe" appears before "moon": <code>pepe.*moon</code></li>
          <li>
            Exclude names or tickers starting with three or more "x" characters: <code>^x{3,}</code>
          </li>
          <li>Exclude tickers made entirely of digits: <code>^\d+$</code></li>
          <li>Exclude the standalone years 2024 through 2029: <code>\b202[4-9]\b</code></li>
        </ul>
      </section>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :term_lists, TermLists.list_term_lists(socket.assigns.current_user))}
  end

  def handle_params(%{"id" => id}, _uri, %{assigns: %{live_action: :edit}} = socket) do
    term_list = TermLists.get_term_list!(socket.assigns.current_user, id)

    {:noreply,
     socket
     |> assign(:term_list, term_list)
     |> assign(:form, to_form(TermLists.change_term_list(term_list)))}
  end

  def handle_params(_params, _uri, %{assigns: %{live_action: :new}} = socket) do
    term_list = TermLists.new_term_list()

    {:noreply,
     socket
     |> assign(:term_list, term_list)
     |> assign(:form, to_form(TermLists.change_term_list(term_list)))}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  def handle_event("validate", %{"term_list" => params}, socket) do
    form =
      socket.assigns.term_list
      |> TermLists.change_term_list(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"term_list" => params}, socket) do
    result =
      case socket.assigns.live_action do
        :new -> TermLists.create_term_list(socket.assigns.current_user, params)
        :edit -> TermLists.update_term_list(socket.assigns.term_list, params)
      end

    case result do
      {:ok, _term_list} ->
        {:noreply, push_navigate(socket, to: ~p"/term-lists")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    socket.assigns.current_user
    |> TermLists.get_term_list!(id)
    |> TermLists.delete_term_list()

    {:noreply,
     assign(socket, :term_lists, TermLists.list_term_lists(socket.assigns.current_user))}
  end

  defp term_count(terms), do: terms |> String.split("\n", trim: true) |> length()

  defp terms_placeholder, do: @terms_placeholder

  defp preview_terms(terms) do
    expressions = String.split(terms, "\n", trim: true)
    preview = expressions |> Enum.take(10) |> Enum.join("\n")

    if length(expressions) > 10 do
      preview <> "\n..."
    else
      preview
    end
  end
end
