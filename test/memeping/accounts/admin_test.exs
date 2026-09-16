defmodule MemePing.Accounts.AdminTest do
  use MemePing.DataCase

  alias MemePing.Accounts
  alias MemePing.Accounts.User
  alias MemePing.Accounts.WalletIdentity

  setup do
    previous_address = Application.get_env(:memeping, :admin_address)
    Application.put_env(:memeping, :admin_address, "0xAdMiN")

    on_exit(fn -> Application.put_env(:memeping, :admin_address, previous_address) end)

    :ok
  end

  test "recognizes the configured EVM wallet address regardless of case" do
    admin = create_user_with_wallet!("evm", "0xadmin")
    solana_user = create_user_with_wallet!("solana", "0xadmin")

    assert Accounts.admin?(admin)
    refute Accounts.admin?(solana_user)
  end

  test "only the configured admin can update a plan" do
    admin = create_user_with_wallet!("evm", "0xadmin")
    other_user = create_user_with_wallet!("evm", "0xother")

    assert {:ok, %{plan: "max"}} = Accounts.update_plan(admin, "max")
    assert {:error, :unauthorized} = Accounts.update_plan(other_user, "max")
  end

  defp create_user_with_wallet!(chain, address) do
    user = Repo.insert!(User.changeset(%User{}, %{}))

    Repo.insert!(
      WalletIdentity.changeset(%WalletIdentity{}, %{
        chain: chain,
        address: address,
        user_id: user.id
      })
    )

    user
  end
end
