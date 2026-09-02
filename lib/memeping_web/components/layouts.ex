defmodule MemePingWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use MemePingWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_user, :any, default: nil, doc: "the logged in user, if any"
  attr :active_tab, :atom, default: nil, doc: "which primary nav tab is active"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="drawer lg:drawer-open">
      <input id="app-drawer" type="checkbox" class="drawer-toggle" />
      <div class="drawer-content flex flex-col min-h-screen">
        <div class="navbar bg-base-100 border-b border-base-300 lg:hidden">
          <label for="app-drawer" class="btn btn-square btn-ghost" aria-label="Open menu">
            <.icon name="hero-bars-3" class="size-5" />
          </label>
          <span class="font-cursive text-xl text-primary ml-2">MemePing</span>
        </div>

        <main class="flex-1 px-4 py-8 sm:px-6 lg:px-10">
          <div class="mx-auto max-w-4xl space-y-4">{render_slot(@inner_block)}</div>
        </main>
      </div>

      <div class="drawer-side z-20">
        <label for="app-drawer" aria-label="Close menu" class="drawer-overlay"></label>
        <aside class="min-h-full w-64 bg-base-200 border-r border-base-300 flex flex-col">
          <a href="/" class="flex items-center gap-2 px-6 py-6">
            <img src={~p"/images/logo.png"} width="32" class="rounded-lg" />
            <span class="font-cursive text-2xl text-primary">MemePing</span>
          </a>
          <nav :if={@current_user} class="flex-1 px-3 space-y-1">
            <a href="/notifiers" class={nav_link_class(@active_tab == :notifiers)}>
              <.icon name="hero-bell" class="size-5" /> Notifiers
            </a>
            <a href="/telegram-channels" class={nav_link_class(@active_tab == :telegram_channels)}>
              <.icon name="hero-chat-bubble-left-right" class="size-5" /> Telegram channels
            </a>
            <a href="/term-lists" class={nav_link_class(@active_tab == :term_lists)}>
              <.icon name="hero-shield-exclamation" class="size-5" /> Forbidden terms
            </a>
            <a href="/plans" class={nav_link_class(@active_tab == :plans)}>
              <.icon name="hero-sparkles" class="size-5" /> Plans
            </a>
          </nav>

          <div class="px-3 py-4 border-t border-base-300 space-y-2">
            <p
              :if={@current_user && Enum.at(@current_user.wallet_identities, 0)}
              class="px-3 font-mono text-xs opacity-60 truncate"
            >
              {Enum.at(@current_user.wallet_identities, 0).address}
            </p>

            <.link
              :if={@current_user}
              href="/logout"
              method="delete"
              class="btn btn-ghost btn-sm w-full justify-start"
            >
              <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" /> Log out
            </.link>
          </div>
        </aside>
      </div>
    </div>
    <.flash_group flash={@flash} />
    """
  end

  defp nav_link_class(active?) do
    [
      "flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
      active? && "bg-primary text-primary-content",
      !active? && "text-base-content/70 hover:bg-base-300 hover:text-base-content"
    ]
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} /> <.flash kind={:error} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
