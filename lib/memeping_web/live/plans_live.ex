defmodule MemePingWeb.PlansLive do
  use MemePingWeb, :live_view

  alias MemePing.Accounts
  alias MemePing.Accounts.Plan
  alias MemePing.Billing

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_tab={:plans}>
      <div class="mb-8 space-y-2">
        <h1 class="text-2xl font-semibold">Plans</h1>
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
            phx-click="choose"
            phx-value-plan={plan.id}
            disabled={plan.id == @current_user.plan or (@paid? and !@admin?)}
            class="btn btn-primary btn-sm w-full"
          >
            {if plan.id == @current_user.plan, do: "Selected", else: "Choose plan"}
          </button>
        </div>
      </div>

      <section :if={@checkout_plan} class="mt-8 space-y-4 border border-base-300 p-5">
        <h2 class="text-lg font-semibold">Choose {Plan.get!(@checkout_plan).name} duration</h2>
        <p class="text-sm text-base-content/70">
          Pay with USDC on Base. You need USDC and a small amount of ETH on Base for gas.
        </p>
        <div class="flex flex-wrap gap-2">
          <button
            :for={days <- Billing.durations()}
            phx-click="pay"
            phx-value-days={days}
            class="btn btn-primary btn-sm"
          >
            {days} days - {price_for(@checkout_plan, days)} USDC
          </button>
        </div>
        <button phx-click="cancel" class="btn btn-ghost btn-sm">Cancel</button>
      </section>

      <div id="base-payment" phx-hook="BasePayment" phx-update="ignore"></div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     assign(socket,
       checkout_plan: nil,
       pending_checkout: nil,
       paid?: Billing.paid?(user),
       admin?: Accounts.admin?(user)
     )}
  end

  def handle_event("choose", %{"plan" => plan_id}, socket) do
    if socket.assigns.admin? do
      case Accounts.update_plan(socket.assigns.current_user, plan_id) do
        {:ok, user} -> {:noreply, assign(socket, :current_user, user)}
        {:error, _} -> {:noreply, socket}
      end
    else
      {:noreply, assign(socket, :checkout_plan, if(plan_id in ["basic", "max"], do: plan_id))}
    end
  end

  def handle_event("cancel", _params, socket),
    do: {:noreply, assign(socket, checkout_plan: nil, pending_checkout: nil)}

  def handle_event("pay", %{"days" => days}, socket) do
    case Billing.checkout(
           socket.assigns.current_user,
           socket.assigns.checkout_plan,
           String.to_integer(days)
         ) do
      {:ok, checkout} ->
        {:noreply,
         socket |> assign(:pending_checkout, checkout) |> push_event("base_payment", checkout)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, checkout_error(reason))}
    end
  end

  def handle_event("payment_submitted", %{"transaction_hash" => transaction_hash}, socket) do
    case socket.assigns.pending_checkout do
      nil ->
        {:noreply, put_flash(socket, :error, "Choose a plan duration before submitting payment.")}

      checkout ->
        case Billing.claim_payment(socket.assigns.current_user, checkout, transaction_hash) do
          {:ok, user} ->
            {:noreply,
             socket
             |> assign(current_user: user, paid?: true, checkout_plan: nil, pending_checkout: nil)
             |> put_flash(:info, "Payment confirmed.")}

          {:error, _} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "Payment could not be verified yet. Please try again shortly."
             )}
        end
    end
  end

  def handle_event("payment_failed", %{"message" => message}, socket),
    do: {:noreply, put_flash(socket, :error, message)}

  defp price_label(%{price_cents: 0}), do: "Free"
  defp price_label(%{price_cents: cents}), do: "$#{div(cents, 100)} / 30 days"

  defp limit_label(nil, label), do: "Unlimited #{label}s"
  defp limit_label(1, label), do: "1 #{label} max"
  defp limit_label(n, label), do: "#{n} #{label}s max"

  defp term_list_limit_label(0), do: "No forbidden term lists"
  defp term_list_limit_label(limit), do: limit_label(limit, "forbidden term list")
  defp price_for(plan_id, days), do: div(Plan.get!(plan_id).price_cents, 100) * div(days, 30)

  defp checkout_error(:evm_wallet_required),
    do: "Connect an EVM wallet with MetaMask to pay on Base."

  defp checkout_error(:treasury_not_configured), do: "Payments are temporarily unavailable."
  defp checkout_error(_reason), do: "This plan is not available for purchase."
end
