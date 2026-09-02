defmodule MemePing.Telegram.Client do
  @moduledoc """
  Behaviour and dispatch module for Telegram Bot API message delivery.
  """

  @callback send_message(String.t(), String.t()) :: :ok | {:error, term()}
  @callback send_photo(String.t(), String.t(), String.t()) :: :ok | {:error, term()}

  @spec send_message(String.t(), String.t()) :: :ok | {:error, term()}
  def send_message(chat_id, message) when is_binary(chat_id) and is_binary(message) do
    implementation().send_message(chat_id, message)
  end

  @spec send_photo(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def send_photo(chat_id, photo_url, caption)
      when is_binary(chat_id) and is_binary(photo_url) and is_binary(caption) do
    implementation().send_photo(chat_id, photo_url, caption)
  end

  defp implementation do
    Application.get_env(:memeping, :telegram_client, MemePing.Telegram.HTTPClient)
  end
end
