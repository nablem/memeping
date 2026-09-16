defmodule MemePing.BillingTest do
  use MemePing.DataCase

  alias MemePing.Accounts.User
  alias MemePing.Accounts.WalletIdentity
  alias MemePing.Billing
  alias MemePing.Billing.Subscription

  setup do
    previous_treasury = Application.get_env(:memeping, :treasury_address)
    previous_client = Application.get_env(:memeping, :base_payment_client)

    Application.put_env(
      :memeping,
      :treasury_address,
      "0xFBb90f2CB250Ad9ae872dB883e071D438D590B9B"
    )

    Application.put_env(:memeping, :base_payment_client, MemePing.Billing.BasePaymentTestClient)

    on_exit(fn ->
      Application.put_env(:memeping, :treasury_address, previous_treasury)
      Application.put_env(:memeping, :base_payment_client, previous_client)
    end)

    user = Repo.insert!(User.changeset(%User{}, %{}))

    Repo.insert!(
      WalletIdentity.changeset(%WalletIdentity{}, %{
        user_id: user.id,
        chain: "evm",
        address: "0xpayer"
      })
    )

    %{user: user}
  end

  test "activates the selected plan for the selected UTC-day duration", %{user: user} do
    assert {:ok, checkout} = Billing.checkout(user, "basic", 90)
    assert checkout.amount_usdc == 57

    transaction_hash = "0x" <> String.duplicate("a", 64)
    assert {:ok, %{plan: "basic"}} = Billing.claim_payment(user, checkout, transaction_hash)

    assert %{
             plan: "basic",
             duration_days: 90,
             amount_usdc: 57,
             started_on: started_on,
             expires_on: expires_on
           } = Repo.one!(Subscription)

    assert started_on == Date.utc_today()
    assert expires_on == Date.add(Date.utc_today(), 90)
  end

  test "does not permit another paid-plan purchase while a subscription is active", %{user: user} do
    assert {:ok, checkout} = Billing.checkout(user, "max", 30)
    assert {:ok, _} = Billing.claim_payment(user, checkout, "0x" <> String.duplicate("b", 64))
    assert {:error, :active_subscription} = Billing.checkout(user, "basic", 30)
  end

  test "resets expired paid users to Free", %{user: user} do
    user = Repo.update!(User.plan_changeset(user, %{plan: "max"}))

    Repo.insert!(
      Subscription.changeset(%Subscription{}, %{
        user_id: user.id,
        plan: "max",
        started_on: Date.add(Date.utc_today(), -30),
        expires_on: Date.utc_today(),
        duration_days: 30,
        transaction_hash: "0x" <> String.duplicate("c", 64),
        payer_address: "0xpayer",
        amount_usdc: 39
      })
    )

    Billing.expire_subscriptions()
    assert Repo.get!(User, user.id).plan == "free"
  end
end
