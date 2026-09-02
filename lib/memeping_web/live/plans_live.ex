defmodule MemePingWeb.PlansLive do
  use MemePingWeb, :live_view

  alias MemePing.Accounts
  alias MemePing.Accounts.Plan

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_tab={:plans}>
      <div class="mb-8 space-y-2">
        <h1 class="text-2xl font-semibold">Plans</h1>
        
        <p class="text-sm">
          <strong class="text-primary">
            Payment is not wired up yet — pick a plan to switch to it instantly.
          </strong>
        </p>
      </div>
      
      <div class="grid gap-4 sm:grid-cols-3">
        <div
          :for={plan <- Plan.all()}
          class={[
            "border p-5 rounded-box flex flex-col gap-4",
            plan.id == @current_user.plan && "border-primary border-2",
            plan.id != @current_user.plan && "border-base-300"
          ]}
        >
          <div>
            <div class="flex items-center gap-2">
              <h2 class="text-lg font-semibold">{plan.name}</h2>
              
              <span :if={plan.id == @current_user.plan} class="badge badge-accent text-white">
                Current plan
              </span>
            </div>
            
            <p class="text-2xl font-semibold mt-2">{price_label(plan)}</p>
            
            <p class="text-xs opacity-70">
              {if plan.duration_days, do: "prepaid, no auto-renewal", else: "\u00A0"}
            </p>
          </div>
          
          <ul class="text-sm space-y-1 flex-1">
            <li>{limit_label(plan.notifier_limit, "notifier")}</li>
            
            <li>{limit_label(plan.telegram_channel_limit, "Telegram channel")}</li>
            
            <li>{term_list_limit_label(plan.term_list_limit)}</li>
          </ul>
          
          <button
            phx-click="select"
            phx-value-plan={plan.id}
            disabled={plan.id == @current_user.plan}
            class="btn btn-primary btn-sm w-full"
          >
            {if plan.id == @current_user.plan, do: "Selected", else: "Choose plan"}
          </button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket), do: {:ok, socket}

  def handle_event("select", %{"plan" => plan_id}, socket) do
    case Accounts.update_plan(socket.assigns.current_user, plan_id) do
      {:ok, user} -> {:noreply, assign(socket, :current_user, user)}
      {:error, _changeset} -> {:noreply, socket}
    end
  end

  defp price_label(%{price_cents: 0}), do: "Free"
  defp price_label(%{price_cents: cents}), do: "$#{div(cents, 100)} / 30 days"

  defp limit_label(nil, label), do: "Unlimited #{label}s"
  defp limit_label(1, label), do: "1 #{label} max"
  defp limit_label(n, label), do: "#{n} #{label}s max"

  defp term_list_limit_label(0), do: "No forbidden term lists"
  defp term_list_limit_label(limit), do: limit_label(limit, "forbidden term list")
end
