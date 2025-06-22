defmodule JidoTest.ExecAsyncTest do
  use JidoTest.ActionCase, async: false

  import ExUnit.CaptureLog

  alias Jido.Action.Error
  alias Jido.Exec
  alias JidoTest.TestActions.BasicAction
  alias JidoTest.TestActions.DelayAction
  alias JidoTest.TestActions.ErrorAction

  @moduletag :capture_log

  describe "run_async/4" do
    test "returns an async_ref with pid and ref" do
      capture_log(fn ->
        result = Exec.run_async(BasicAction, %{value: 5})
        assert is_map(result)
        assert is_pid(result.pid)
        assert is_reference(result.ref)
      end)
    end
  end

  describe "await/2" do
    test "returns the result of a successful async action" do
      capture_log(fn ->
        async_ref = Exec.run_async(BasicAction, %{value: 5}, %{}, timeout: 50)
        assert {:ok, %{value: 5}} = Exec.await(async_ref)
      end)
    end

    test "returns an error for a failed async action" do
      capture_log(fn ->
        async_ref = Exec.run_async(ErrorAction, %{error_type: :runtime}, %{}, timeout: 50)

        assert {:error, %Error{type: :execution_error, message: message}} =
                 Exec.await(async_ref)

        assert message =~ "Runtime error"
      end)
    end

    test "returns a timeout error when the action exceeds the timeout" do
      capture_log(fn ->
        async_ref = Exec.run_async(DelayAction, %{delay: 200}, %{}, timeout: 75)

        assert {:error, %Error{type: :timeout, message: "Async action timed out after 50ms"}} =
                 Exec.await(async_ref, 50)
      end)
    end
  end

  describe "cancel/1" do
    test "successfully cancels an async action" do
      capture_log(fn ->
        async_ref = Exec.run_async(BasicAction, %{value: 5})
        assert :ok = Exec.cancel(async_ref)

        refute Process.alive?(async_ref.pid)
      end)
    end

    test "returns ok when cancelling an already completed action" do
      capture_log(fn ->
        async_ref = Exec.run_async(BasicAction, %{value: 5})

        Exec.await(async_ref)
        assert :ok = Exec.cancel(async_ref)
      end)
    end

    test "accepts a pid directly" do
      capture_log(fn ->
        async_ref = Exec.run_async(BasicAction, %{value: 5})
        assert :ok = Exec.cancel(async_ref.pid)
        refute Process.alive?(async_ref.pid)
      end)
    end

    test "returns an error for invalid input" do
      assert {:error, %Error{type: :invalid_async_ref}} = Exec.cancel("invalid")
    end
  end

  test "integration of run_async, await, and cancel" do
    capture_log(fn ->
      test_pid = self()
      async_ref = Exec.run_async(DelayAction, %{delay: 2000}, %{}, timeout: 2000)

      spawn(fn ->
        result = Exec.await(async_ref, 100)
        send(test_pid, {:await_result, result})
      end)

      Process.sleep(50)
      Exec.cancel(async_ref)

      receive do
        {:await_result, result} ->
          assert {:error, %Error{type: :timeout} = error} = result
          assert error.message =~ "Async action timed out after 100ms"
      after
        2000 ->
          flunk("Await did not complete in time")
      end

      refute Process.alive?(async_ref.pid)
    end)
  end
end
