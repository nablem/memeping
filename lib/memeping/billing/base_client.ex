defmodule MemePing.Billing.BaseClient do
  @callback verify_payment(String.t(), String.t(), String.t(), pos_integer()) ::
              :ok | {:error, atom()}
end
