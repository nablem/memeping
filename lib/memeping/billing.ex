defmodule MemePing.Billing do
  import Ecto.Query

  alias MemePing.Accounts.Plan
  alias MemePing.Accounts.User
  alias MemePing.Accounts.WalletIdentity
  alias MemePing.Billing.Subscription
  alias MemePing.Repo

  @durations [30, 90, 180, 360]

  def durations, do: @durations

  def active_subscription(%User{id: user_id}) do
    Repo.one(
      from subscription in Subscription,
        where: subscription.user_id == ^user_id and subscription.expires_on > ^Date.utc_today()
    )
  end

  def paid?(user), do: not is_nil(active_subscription(user))

  def checkout(user, plan_id, duration_days) do
    with true <- plan_id in ["basic", "max"],
         true <- duration_days in @durations,
         false <- paid?(user),
         treasury when is_binary(treasury) and treasury != "" <-
           Application.get_env(:memeping, :treasury_address),
         [payer | _] <- evm_addresses(user) do
      amount_usdc = div(Plan.get!(plan_id).price_cents, 100) * div(duration_days, 30)

      {:ok,
       %{
         plan: plan_id,
         duration_days: duration_days,
         payer: payer,
         treasury: treasury,
         amount_usdc: amount_usdc
       }}
    else
      [] -> {:error, :evm_wallet_required}
      nil -> {:error, :treasury_not_configured}
      false -> {:error, :invalid_purchase}
      _ -> {:error, :active_subscription}
    end
  end

  def claim_payment(user, checkout, transaction_hash) do
    with true <- valid_hash?(transaction_hash),
         :ok <-
           payment_client().verify_payment(
             transaction_hash,
             checkout.payer,
             checkout.treasury,
             checkout.amount_usdc * 1_000_000
           ) do
      started_on = Date.utc_today()
      expires_on = Date.add(started_on, checkout.duration_days)

      Repo.transaction(fn ->
        Repo.insert!(
          Subscription.changeset(
            %Subscription{},
            Map.merge(checkout, %{
              user_id: user.id,
              transaction_hash: transaction_hash,
              payer_address: checkout.payer,
              started_on: started_on,
              expires_on: expires_on
            })
          )
        )

        Repo.update!(User.plan_changeset(user, %{plan: checkout.plan}))
      end)
    else
      false -> {:error, :invalid_transaction_hash}
      {:error, _} = error -> error
    end
  end

  def expire_subscriptions do
    user_ids =
      Repo.all(
        from subscription in Subscription,
          where: subscription.expires_on <= ^Date.utc_today(),
          select: subscription.user_id
      )

    Repo.update_all(from(user in User, where: user.id in ^user_ids and user.plan != "free"),
      set: [plan: "free"]
    )
  end

  defp evm_addresses(user),
    do:
      Repo.all(
        from identity in WalletIdentity,
          where: identity.user_id == ^user.id and identity.chain == "evm",
          select: identity.address
      )

  defp payment_client,
    do: Application.get_env(:memeping, :base_payment_client, MemePing.Billing.BaseHTTPClient)

  defp valid_hash?("0x" <> hash), do: String.match?(hash, ~r/^[0-9a-fA-F]{64}$/)
  defp valid_hash?(_), do: false
end
