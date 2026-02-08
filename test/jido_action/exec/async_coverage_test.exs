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
      monitor_ref = make_ref()
      pid = spawn(fn -> :ok end)
      result = {:ok, %{value: 123}}

      # First DOWN, then in-flight async result.
      send(self(), {:DOWN, monitor_ref, :process, pid, :normal})
      send(self(), {:action_async_result, ref, result})

      async_ref = %{ref: ref, pid: pid, owner: self(), monitor_ref: monitor_ref}
      assert ^result = Async.await(async_ref, 1_000)
    end

    test "returns execution error when DOWN normal arrives without result" do
      ref = make_ref()
      monitor_ref = make_ref()
      pid = spawn(fn -> :ok end)

      send(self(), {:DOWN, monitor_ref, :process, pid, :normal})

      async_ref = %{ref: ref, pid: pid, owner: self(), monitor_ref: monitor_ref}

      assert {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} =
               Async.await(async_ref, 1_000)

      assert message =~ "Process completed but result was not received"
    end

    test "returns execution error when DOWN carries non-normal reason" do
      ref = make_ref()
      monitor_ref = make_ref()
      pid = spawn(fn -> :ok end)

      send(self(), {:DOWN, monitor_ref, :process, pid, :killed})

      async_ref = %{ref: ref, pid: pid, owner: self(), monitor_ref: monitor_ref}

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
