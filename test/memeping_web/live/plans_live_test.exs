defmodule MemePingWeb.PlansLiveTest do
  use MemePingWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MemePing.Accounts.User
  alias MemePing.Accounts.WalletIdentity
  alias MemePing.Repo

  setup %{conn: conn} do
    previous_address = Application.get_env(:memeping, :admin_address)
    Application.put_env(:memeping, :admin_address, "0xadmin")

    on_exit(fn -> Application.put_env(:memeping, :admin_address, previous_address) end)

    %{conn: conn}
  end

  test "allows the configured admin to select a plan", %{conn: conn} do
    user = create_user_with_wallet!("0xadmin")
    conn = Plug.Test.init_test_session(conn, %{"user_id" => user.id})
    {:ok, view, _html} = live(conn, ~p"/plans")

    view
    |> element("button[phx-value-plan='max']")
    |> render_click()

    assert Repo.get!(User, user.id).plan == "max"
  end

  test "does not change plans for other users", %{conn: conn} do
    user = create_user_with_wallet!("0xother")
    conn = Plug.Test.init_test_session(conn, %{"user_id" => user.id})
    {:ok, view, _html} = live(conn, ~p"/plans")

    view
    |> element("button[phx-value-plan='max']")
    |> render_click()

    assert Repo.get!(User, user.id).plan == "free"
  end

  test "shows the optional admin attribution in the app footer", %{conn: conn} do
    previous_name = Application.get_env(:memeping, :admin_name)
    Application.put_env(:memeping, :admin_name, "Nabil")
    on_exit(fn -> Application.put_env(:memeping, :admin_name, previous_name) end)

    user = create_user_with_wallet!("0xother")
    conn = Plug.Test.init_test_session(conn, %{"user_id" => user.id})
    {:ok, view, _html} = live(conn, ~p"/plans")

    assert has_element?(view, "footer", "Created with passion by Nabil")
  end

  test "shows the support contact in the app footer", %{conn: conn} do
    user = create_user_with_wallet!("0xother")
    conn = Plug.Test.init_test_session(conn, %{"user_id" => user.id})
    {:ok, view, _html} = live(conn, ~p"/plans")

    assert has_element?(
             view,
             "footer a[href='mailto:contact@memeping.com']",
             "contact@memeping.com"
           )
  end

  defp create_user_with_wallet!(address) do
    user = Repo.insert!(User.changeset(%User{}, %{}))

    Repo.insert!(
      WalletIdentity.changeset(%WalletIdentity{}, %{
        chain: "evm",
        address: address,
        user_id: user.id
      })
    )

    user
  end
end
