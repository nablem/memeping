defmodule MemePingWeb.Router do
  use MemePingWeb, :router

  import MemePingWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MemePingWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :fetch_current_user
  end

  pipeline :authenticated do
    plug :require_authenticated_user
  end

  scope "/", MemePingWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/login", WalletAuthController, :new
    delete "/logout", WalletAuthController, :delete
  end

  scope "/auth/wallet", MemePingWeb do
    pipe_through :api

    post "/nonce", WalletAuthController, :nonce
    post "/verify", WalletAuthController, :verify
  end

  scope "/", MemePingWeb do
    pipe_through [:browser, :authenticated]

    live_session :require_authenticated_user,
      on_mount: [{MemePingWeb.UserAuth, :ensure_authenticated}] do
      live "/notifiers", NotifiersLive, :index
      live "/notifiers/new", NotifiersLive, :new
      live "/notifiers/:id/edit", NotifiersLive, :edit
      live "/telegram-channels", TelegramChannelsLive, :index
      live "/term-lists", TermListsLive, :index
      live "/term-lists/new", TermListsLive, :new
      live "/term-lists/:id/edit", TermListsLive, :edit
      live "/plans", PlansLive, :index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", MemePingWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:memeping, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MemePingWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
