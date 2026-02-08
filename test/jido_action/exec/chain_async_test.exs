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
      async_ref =
        Chain.chain(
          [Add, {DelayAction, %{delay: 5_000}}, Multiply],
          %{value: 5, amount: 1},
          async: true
        )

      assert {:error, %Jido.Action.Error.TimeoutError{}} =
               Chain.await(async_ref, 100)
    end
  end

  describe "chain async await with completed result" do
    test "returns result for already-completed async chain" do
      async_ref =
        Chain.chain(
          [Add, Multiply],
          %{value: 5, amount: 2},
          async: true
        )

      # Give time for the chain to complete
      Process.sleep(100)

      assert {:ok, %{value: 14}} = Chain.await(async_ref, 5_000)
    end
  end

  describe "chain async await from non-owner process" do
    test "fails fast when awaiting from non-owner" do
      async_ref =
        Chain.chain(
          [Add, Multiply],
          %{value: 5, amount: 2},
          async: true
        )

      # Modify async_ref to simulate non-owner
      fake_ref = %{async_ref | owner: spawn(fn -> :ok end)}

      assert {:error, %Jido.Action.Error.InvalidInputError{message: message}} =
               Chain.await(fake_ref, 5_000)

      assert message =~ "owner process"
    end
  end

  describe "chain async await with stale monitor" do
    test "uses a fresh monitor for dead process and returns quickly" do
      pid = spawn(fn -> :ok end)
      stale_monitor_ref = Process.monitor(pid)
      assert_receive {:DOWN, ^stale_monitor_ref, :process, ^pid, :normal}
      Process.demonitor(stale_monitor_ref, [:flush])

      async_ref = %{ref: make_ref(), pid: pid, owner: self(), monitor_ref: stale_monitor_ref}

      {elapsed_us, await_result} = :timer.tc(fn -> Chain.await(async_ref, 100) end)

      assert {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} = await_result
      assert message =~ "Server error in async chain: :noproc"
      assert elapsed_us < 200_000
    end
  end

  describe "legacy map compatibility" do
    test "warns when awaiting with legacy map async_ref" do
      async_ref =
        Chain.chain(
          [Add, Multiply],
          %{value: 5, amount: 2},
          async: true
        )

      legacy_ref = Map.from_struct(async_ref)

      log =
        capture_log(fn ->
          assert {:ok, %{value: 14}} = Chain.await(legacy_ref, 5_000)
        end)

      assert log =~ "Jido.Exec.Chain.await/2 received a legacy map async_ref"
    end

    test "warns when cancelling with legacy map async_ref" do
      async_ref =
        Chain.chain(
          [{DelayAction, %{delay: 5_000}}],
          %{},
          async: true
        )

      legacy_ref = Map.from_struct(async_ref)

      log =
        capture_log(fn ->
          assert :ok = Chain.cancel(legacy_ref)
        end)

      assert log =~ "Jido.Exec.Chain.cancel/1 received a legacy map async_ref"
    end
  end
end
