defmodule MemePing.Accounts do
  @moduledoc """
  Wallet-based authentication: nonce challenges, signature verification, user lookup.
  """

  import Ecto.Query

  alias MemePing.Accounts.Plan
  alias MemePing.Accounts.User
  alias MemePing.Accounts.WalletIdentity
  alias MemePing.Accounts.Wallet
  alias MemePing.Repo

  @challenge_ttl_seconds 300
  @session_key "wallet_challenge"

  @spec get_user(pos_integer()) :: User.t() | nil
  def get_user(id), do: Repo.get(User, id)

  @spec get_user_with_identities(pos_integer()) :: User.t() | nil
  def get_user_with_identities(id) do
    case Repo.get(User, id) do
      nil -> nil
      user -> Repo.preload(user, :wallet_identities)
    end
  end

  @doc """
  Builds a fresh sign-in message for the given chain/address and returns the session
  entry that should be stored (via `Plug.Conn.put_session/3`) alongside it.
  """
  @spec build_challenge(WalletIdentity.chain(), String.t()) :: {String.t(), map()}
  def build_challenge(chain, address) when is_binary(chain) and is_binary(address) do
    nonce = 16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
    issued_at = System.system_time(:second)

    message = """
    Sign in to MemePing

    Address: #{address}
    Nonce: #{nonce}
    Issued at: #{issued_at}
    """

    challenge = %{
      "chain" => chain,
      "address" => normalize_address(chain, address),
      "nonce" => nonce,
      "issued_at" => issued_at
    }

    {message, %{@session_key => challenge}}
  end

  @doc """
  Verifies a signed challenge against what was stored in the session and, on success,
  finds or creates the matching user. Returns `{:ok, user}` or `{:error, reason}`.
  """
  @spec verify_login(map() | nil, map()) :: {:ok, User.t()} | {:error, atom()}
  def verify_login(session_challenge, %{
        "chain" => chain,
        "address" => address,
        "signature" => signature
      }) do
    with {:ok, challenge} <- fetch_valid_challenge(session_challenge, chain, address),
         message <- rebuild_message(challenge),
         true <- verify_signature(chain, message, signature, address) do
      find_or_create_user(chain, address)
    else
      _ -> {:error, :invalid_signature}
    end
  end

  def verify_login(_session_challenge, _params), do: {:error, :invalid_request}

  defp fetch_valid_challenge(nil, _chain, _address), do: {:error, :no_challenge}

  defp fetch_valid_challenge(challenge, chain, address) do
    now = System.system_time(:second)

    cond do
      challenge["chain"] != chain -> {:error, :chain_mismatch}
      challenge["address"] != normalize_address(chain, address) -> {:error, :address_mismatch}
      now - challenge["issued_at"] > @challenge_ttl_seconds -> {:error, :expired}
      true -> {:ok, challenge}
    end
  end

  defp rebuild_message(challenge) do
    """
    Sign in to MemePing

    Address: #{challenge["address"]}
    Nonce: #{challenge["nonce"]}
    Issued at: #{challenge["issued_at"]}
    """
  end

  defp verify_signature("evm", message, signature, address),
    do: Wallet.EVM.verify(message, signature, address)

  defp verify_signature("solana", message, signature, address),
    do: Wallet.Solana.verify(message, signature, address)

  defp verify_signature(_chain, _message, _signature, _address), do: false

  # EVM hex addresses are case-insensitive; Base58 Solana addresses are case-sensitive.
  defp normalize_address("evm", address), do: String.downcase(address)
  defp normalize_address(_chain, address), do: address

  defp find_or_create_user(chain, address) do
    address = normalize_address(chain, address)

    case Repo.get_by(WalletIdentity, chain: chain, address: address) do
      %WalletIdentity{} = identity ->
        {:ok, Repo.get!(User, identity.user_id)}

      nil ->
        Repo.transaction(fn ->
          user = Repo.insert!(User.changeset(%User{}, %{}))

          %WalletIdentity{}
          |> WalletIdentity.changeset(%{chain: chain, address: address, user_id: user.id})
          |> Repo.insert!()

          user
        end)
    end
  end

  @spec session_key() :: String.t()
  def session_key, do: @session_key

  @spec wallet_identities(User.t()) :: [WalletIdentity.t()]
  def wallet_identities(%User{id: id}) do
    WalletIdentity
    |> where([w], w.user_id == ^id)
    |> Repo.all()
  end

  @doc """
  Whether the user owns the optional configured EVM admin address.

  When no `ADMIN_ADDRESS` environment variable is configured, no user can
  switch plans until billing is implemented.
  """
  @spec admin?(User.t()) :: boolean()
  def admin?(%User{id: user_id}) do
    case Application.get_env(:memeping, :admin_address) do
      admin_address when is_binary(admin_address) and admin_address != "" ->
        WalletIdentity
        |> where([identity], identity.user_id == ^user_id and identity.chain == "evm")
        |> select([identity], identity.address)
        |> Repo.all()
        |> Enum.any?(&(String.downcase(&1) == String.downcase(admin_address)))

      _ ->
        false
    end
  end

  @doc "Returns the user's configured plan limit for a managed resource."
  @spec resource_limit(User.t(), :notifier | :telegram_channel | :term_list) ::
          pos_integer() | nil
  def resource_limit(%User{plan: plan_id}, resource) do
    plan_id
    |> Plan.get!()
    |> Plan.resource_limit(resource)
  end

  @spec update_plan(User.t(), String.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  def update_plan(%User{} = user, plan_id) do
    if admin?(user) do
      user
      |> User.plan_changeset(%{plan: plan_id})
      |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end
end
