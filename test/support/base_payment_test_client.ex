defmodule MemePing.Billing.BasePaymentTestClient do
  @behaviour MemePing.Billing.BaseClient

  def verify_payment(_transaction_hash, _payer, _treasury, _amount) do
    Application.get_env(:memeping, :base_payment_test_result, :ok)
  end
end
