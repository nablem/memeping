defmodule MemePingWeb.NotifiersLiveTest do
  use MemePingWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MemePing.Accounts.User
  alias MemePing.Repo

  setup %{conn: conn} do
    user = Repo.insert!(User.changeset(%User{}, %{}))
    conn = Plug.Test.init_test_session(conn, %{"user_id" => user.id})
    %{conn: conn, user: user}
  end

  test "lists an empty state, creates, edits and deletes a notifier", %{conn: conn, user: user} do
    {:ok, _index_live, html} = live(conn, ~p"/notifiers")
    assert html =~ "No notifiers yet"

    {:ok, new_live, _html} = live(conn, ~p"/notifiers/new")

    new_live
    |> form("#notifier-form",
      notifier: %{
        "name" => "New Solana pairs",
        "chain" => "solana",
        "criteria" => %{"market_cap_min" => "10000", "liquidity_min" => "5000"}
      }
    )
    |> render_submit()

    assert_redirect(new_live, ~p"/notifiers")

    {:ok, _index_live, html} = live(conn, ~p"/notifiers")
    assert html =~ "New Solana pairs"

    [notifier] = MemePing.Notifications.list_notifiers(user)
    assert notifier.criteria.market_cap_min == 10_000

    {:ok, edit_live, _html} = live(conn, ~p"/notifiers/#{notifier}/edit")

    edit_live
    |> form("#notifier-form", notifier: %{"name" => "Renamed notifier"})
    |> render_submit()

    assert_redirect(edit_live, ~p"/notifiers")

    {:ok, index_live, html} = live(conn, ~p"/notifiers")
    assert html =~ "Renamed notifier"

    index_live
    |> element("a", "Delete")
    |> render_click()

    html = render(index_live)
    assert html =~ "No notifiers yet"
  end

  test "rejects a duplicate notifier name for the same user", %{conn: conn} do
    {:ok, first_live, _html} = live(conn, ~p"/notifiers/new")

    first_live
    |> form("#notifier-form",
      notifier: %{"name" => "Solana calls", "chain" => "solana"}
    )
    |> render_submit()

    {:ok, second_live, _html} = live(conn, ~p"/notifiers/new")

    second_live
    |> form("#notifier-form",
      notifier: %{"name" => "Solana calls", "chain" => "ethereum"}
    )
    |> render_submit()

    assert has_element?(second_live, "#notifier-form p.text-error", "has already been taken")
  end

  test "renders large numeric criteria without exponential notation", %{conn: conn, user: user} do
    {:ok, notifier} =
      MemePing.Notifications.create_notifier(user, %{
        "name" => "Large cap calls",
        "chain" => "solana",
        "criteria" => %{"market_cap_min" => "50000"}
      })

    {:ok, edit_live, _html} = live(conn, ~p"/notifiers/#{notifier}/edit")

    assert has_element?(
             edit_live,
             "input[name='notifier[criteria][market_cap_min]'][value='50000.0']"
           )
  end

  test "rejects notifier names longer than 25 characters", %{conn: conn} do
    {:ok, live_view, _html} = live(conn, ~p"/notifiers/new")

    live_view
    |> form("#notifier-form",
      notifier: %{
        "name" => "This notifier name is too long",
        "chain" => "solana"
      }
    )
    |> render_submit()

    assert has_element?(
             live_view,
             "#notifier-form p.text-error",
             "should be at most 25 character"
           )
  end
end
