defmodule JidoTest.Exec.AsyncCoverageTest do
  @moduledoc """
  Additional coverage tests for Jido.Exec.Async.
  """
  use JidoTest.ActionCase, async: false

  import ExUnit.CaptureLog

  alias Jido.Exec.Async
  alias JidoTest.TestActions.Add

  @moduletag :capture_log

  describe "cancel/1" do
    test "returns quickly when async_ref monitor is stale" do
      pid = spawn(fn -> :ok end)
      stale_monitor_ref = Process.monitor(pid)
      assert_receive {:DOWN, ^stale_monitor_ref, :process, ^pid, :normal}
      Process.demonitor(stale_monitor_ref, [:flush])

      async_ref = %{pid: pid, owner: self(), monitor_ref: stale_monitor_ref}

      {elapsed_us, result} = :timer.tc(fn -> Async.cancel(async_ref) end)
      assert :ok = result
      assert elapsed_us < 200_000
    end

    test "cancels with async_ref from non-owner process" do
      capture_log(fn ->
        async_ref = Async.start(Add, %{value: 5, amount: 1})
        # Modify the owner to simulate non-owner
        modified_ref = %{async_ref | owner: spawn(fn -> :ok end)}
        assert :ok = Async.cancel(modified_ref)
      end)
    end

    test "cancels with just a pid" do
      capture_log(fn ->
        async_ref = Async.start(Add, %{value: 5, amount: 1})
        assert :ok = Async.cancel(async_ref.pid)
      end)
    end

    test "returns error for invalid cancel argument" do
      assert {:error, %Jido.Action.Error.InvalidInputError{}} = Async.cancel("invalid")
      assert {:error, %Jido.Action.Error.InvalidInputError{}} = Async.cancel(42)
      assert {:error, %Jido.Action.Error.InvalidInputError{}} = Async.cancel(nil)
    end
  end

  describe "await/2" do
    test "uses a fresh monitor when async_ref monitor is stale" do
      pid = spawn(fn -> :ok end)
      stale_monitor_ref = Process.monitor(pid)
      assert_receive {:DOWN, ^stale_monitor_ref, :process, ^pid, :normal}
      Process.demonitor(stale_monitor_ref, [:flush])

      async_ref = %{ref: make_ref(), pid: pid, owner: self(), monitor_ref: stale_monitor_ref}

      {elapsed_us, await_result} = :timer.tc(fn -> Async.await(async_ref, 100) end)

      assert {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} = await_result
      assert message =~ "Server error in async action: :noproc"
      assert elapsed_us < 200_000
    end

    test "returns result for completed action" do
      capture_log(fn ->
        async_ref = Async.start(Add, %{value: 10, amount: 5})
        assert {:ok, %{value: 15}} = Async.await(async_ref, 5_000)
      end)
    end

    test "returns result using default timeout" do
      capture_log(fn ->
        async_ref = Async.start(Add, %{value: 10, amount: 5})
        assert {:ok, %{value: 15}} = Async.await(async_ref)
      end)
    end

    test "handles DOWN normal and then receives result in grace window" do
      ref = make_ref()

      pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      result = {:ok, %{value: 123}}
      parent = self()

      spawn(fn ->
        Process.sleep(10)
        send(pid, :stop)
      end)

      spawn(fn ->
        Process.sleep(20)
        send(parent, {:action_async_result, ref, result})
      end)

      async_ref = %{ref: ref, pid: pid}
      assert ^result = Async.await(async_ref, 1_000)
    end

    test "returns execution error when DOWN normal arrives without result" do
      pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      spawn(fn ->
        Process.sleep(10)
        send(pid, :stop)
      end)

      async_ref = %{ref: make_ref(), pid: pid}

      assert {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} =
               Async.await(async_ref, 1_000)

      assert message =~ "Process completed but result was not received"
    end

    test "returns execution error when DOWN carries non-normal reason" do
      pid =
        spawn(fn ->
          receive do
            :crash -> Process.exit(self(), :kill)
          end
        end)

      spawn(fn ->
        Process.sleep(10)
        send(pid, :crash)
      end)

      async_ref = %{ref: make_ref(), pid: pid}

      assert {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} =
               Async.await(async_ref, 1_000)

      assert message =~ "Server error in async action"
    end

    test "flushes extra async result and down messages after returning" do
      ref = make_ref()
      monitor_ref = make_ref()
      pid = spawn(fn -> Process.sleep(200) end)
      result = {:ok, %{value: 9}}

      send(self(), {:action_async_result, ref, result})

      # Keep flush_messages/4 busy enough to hit recursion and base case paths.
      for _ <- 1..9 do
        send(self(), {:action_async_result, ref, {:ok, %{value: :extra}}})
      end

      send(self(), {:DOWN, monitor_ref, :process, pid, :normal})

      async_ref = %{ref: ref, pid: pid, owner: self(), monitor_ref: monitor_ref}
      assert ^result = Async.await(async_ref, 1_000)
    end

    test "timeout path escalates to kill when process traps shutdown" do
      pid =
        spawn(fn ->
          Process.flag(:trap_exit, true)

          receive do
            {:EXIT, _from, :shutdown} ->
              Process.sleep(:infinity)
          end
        end)

      async_ref = %{ref: make_ref(), pid: pid}

      assert {:error, %Jido.Action.Error.TimeoutError{}} = Async.await(async_ref, 0)
    end
  end
end
