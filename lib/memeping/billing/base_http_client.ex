defmodule MemePing.Billing.BaseHTTPClient do
  @behaviour MemePing.Billing.BaseClient

  @usdc_contract "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"
  @transfer_topic "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

  @impl true
  def verify_payment(transaction_hash, payer, treasury, amount) do
    with {:ok, receipt} <- receipt(transaction_hash),
         true <- receipt["status"] == "0x1" and is_binary(receipt["blockNumber"]),
         true <- transfer?(receipt["logs"], payer, treasury, amount) do
      :ok
    else
      false -> {:error, :payment_not_found}
      {:error, _} = error -> error
    end
  end

  defp receipt(transaction_hash) do
    case Req.post(Application.fetch_env!(:memeping, :base_rpc_url),
           json: %{
             jsonrpc: "2.0",
             id: 1,
             method: "eth_getTransactionReceipt",
             params: [transaction_hash]
           }
         ) do
      {:ok, %{status: 200, body: %{"result" => receipt}}} when not is_nil(receipt) ->
        {:ok, receipt}

      _ ->
        {:error, :base_rpc_unavailable}
    end
  end

  defp transfer?(logs, payer, treasury, amount) when is_list(logs) do
    Enum.any?(logs, fn log ->
      normalize(log["address"]) == @usdc_contract and
        sender(log["topics"]) == normalize(payer) and
        recipient(log["topics"]) == normalize(treasury) and
        value(log["data"]) == amount
    end)
  end

  defp transfer?(_, _, _, _), do: false
  defp sender([@transfer_topic, from | _]), do: topic_address(from)
  defp sender(_), do: nil
  defp recipient([@transfer_topic, _from, to | _]), do: topic_address(to)
  defp recipient(_), do: nil

  defp topic_address("0x" <> topic),
    do: ("0x" <> String.slice(topic, -40, 40)) |> String.downcase()

  defp topic_address(_), do: nil
  defp value("0x" <> hex), do: hex |> Base.decode16!(case: :mixed) |> :binary.decode_unsigned()
  defp value(_), do: nil
  defp normalize(address) when is_binary(address), do: String.downcase(address)
end
