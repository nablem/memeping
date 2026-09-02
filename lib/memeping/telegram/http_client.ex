defmodule MemePing.Telegram.HTTPClient do
  @moduledoc false

  @behaviour MemePing.Telegram.Client
  @api_base_url "https://api.telegram.org"

  @impl true
  def send_message(chat_id, message) do
    with {:ok, token} <- bot_token(),
         {:ok, response} <-
           Req.post("#{@api_base_url}/bot#{token}/sendMessage",
             json: %{
               chat_id: chat_id,
               text: message,
               disable_web_page_preview: true,
               parse_mode: "HTML"
             }
           ) do
      handle_response(response)
    end
  end

  @impl true
  def send_photo(chat_id, photo_url, caption) do
    with {:ok, token} <- bot_token(),
         {:ok, response} <-
           Req.post("#{@api_base_url}/bot#{token}/sendPhoto",
             json: %{chat_id: chat_id, photo: photo_url, caption: caption, parse_mode: "HTML"}
           ) do
      handle_response(response)
    end
  end

  defp handle_response(response) do
    case response do
      %{status: 200, body: %{"ok" => true}} -> :ok
      %{body: %{"description" => description}} -> {:error, {:telegram_api, description}}
      %{status: status} -> {:error, {:telegram_api, "request failed with status #{status}"}}
    end
  end

  defp bot_token do
    case Application.get_env(:memeping, :telegram_bot_token) do
      token when is_binary(token) and token != "" -> {:ok, token}
      _ -> {:error, :missing_telegram_bot_token}
    end
  end
end
