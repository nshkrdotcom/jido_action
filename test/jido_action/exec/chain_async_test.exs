defmodule JidoTest.Exec.ChainAsyncTest do
  @moduledoc """
  Tests for Chain async await paths to improve chain.ex coverage.
  """
  use JidoTest.ActionCase, async: false

  import ExUnit.CaptureLog

  alias Jido.Exec.Chain
  alias JidoTest.TestActions.Add
  alias JidoTest.TestActions.DelayAction
  alias JidoTest.TestActions.Multiply

  @moduletag :capture_log

  describe "chain async await timeout" do
    test "returns timeout error when chain takes too long" do
      capture_log(fn ->
        async_ref =
          Chain.chain(
            [Add, {DelayAction, %{delay: 5_000}}, Multiply],
            %{value: 5, amount: 1},
            async: true
          )

        assert {:error, %Jido.Action.Error.TimeoutError{}} =
                 Chain.await(async_ref, 100)
      end)
    end
  end

  describe "chain async await with completed result" do
    test "returns result for already-completed async chain" do
      capture_log(fn ->
        async_ref =
          Chain.chain(
            [Add, Multiply],
            %{value: 5, amount: 2},
            async: true
          )

        # Give time for the chain to complete
        Process.sleep(100)

        assert {:ok, %{value: 14}} = Chain.await(async_ref, 5_000)
      end)
    end
  end

  describe "chain async await from non-owner process" do
    test "creates new monitor when awaiting from non-owner" do
      capture_log(fn ->
        async_ref =
          Chain.chain(
            [Add, Multiply],
            %{value: 5, amount: 2},
            async: true
          )

        # Modify async_ref to simulate non-owner
        fake_ref = %{async_ref | owner: spawn(fn -> :ok end)}

        # Should still work - creates new monitor
        assert {:ok, %{value: 14}} = Chain.await(fake_ref, 5_000)
      end)
    end
  end
end
