defmodule MemePing.Discovery.RecorderTest do
  use MemePing.DataCase

  alias MemePing.Discovery.Recorder
  alias MemePing.Discovery.Token

  setup do
    previous = Application.get_env(:memeping, :dex_screener_test_result)

    on_exit(fn ->
      if previous do
        Application.put_env(:memeping, :dex_screener_test_result, previous)
      else
        Application.delete_env(:memeping, :dex_screener_test_result)
      end
    end)

    :ok
  end

  describe "process_token/1" do
    test "inserts a new token for a supported chain" do
      Recorder.process_token(%{
        "chainId" => "solana",
        "tokenAddress" => "SoLaNaAddr111",
        "description" => "to the moon"
      })

      token = Repo.get_by(Token, chain_id: "solana", token_address: "SoLaNaAddr111")
      assert token.description == "to the moon"
      assert token.active == true
    end

    test "upserts on (chain_id, token_address) conflict, replacing only description" do
      Recorder.process_token(%{
        "chainId" => "base",
        "tokenAddress" => "BaseAddr1",
        "description" => "first pass"
      })

      %Token{id: id, updated_at: first_updated_at} =
        Repo.get_by(Token, chain_id: "base", token_address: "BaseAddr1")

      Recorder.process_token(%{
        "chainId" => "base",
        "tokenAddress" => "BaseAddr1",
        "description" => "second pass"
      })

      token = Repo.get_by(Token, chain_id: "base", token_address: "BaseAddr1")
      assert token.id == id
      assert token.description == "second pass"
      assert NaiveDateTime.compare(token.updated_at, first_updated_at) in [:gt, :eq]
      assert Repo.aggregate(Token, :count) == 1
    end

    test "allows the same token address on two different chains" do
      Recorder.process_token(%{"chainId" => "solana", "tokenAddress" => "SharedAddr"})
      Recorder.process_token(%{"chainId" => "ethereum", "tokenAddress" => "SharedAddr"})

      assert Repo.aggregate(Token, :count) == 2
    end
  end

  describe "polling" do
    test "persists profiles for supported chains and skips unsupported ones" do
      Application.put_env(
        :memeping,
        :dex_screener_test_result,
        {:ok,
         [
           %{"chainId" => "solana", "tokenAddress" => "SoLaNaAddr222", "description" => "moon"},
           %{"chainId" => "notarealchain", "tokenAddress" => "SkipMe", "description" => "nope"}
         ]}
      )

      pid = start_supervised!(Recorder)
      send(pid, :poll)
      _ = :sys.get_state(pid)

      assert Repo.get_by(Token, chain_id: "solana", token_address: "SoLaNaAddr222")
      refute Repo.get_by(Token, token_address: "SkipMe")
    end

    test "keeps running after an API error" do
      Application.put_env(:memeping, :dex_screener_test_result, {:error, :timeout})

      pid = start_supervised!(Recorder)
      send(pid, :poll)
      _ = :sys.get_state(pid)

      assert Process.alive?(pid)
    end
  end
end
