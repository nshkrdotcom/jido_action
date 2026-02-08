defmodule JidoTest.ExecAsyncTest do
  use JidoTest.ActionCase, async: false

  alias Jido.Exec
  alias JidoTest.TestActions.BasicAction
  alias JidoTest.TestActions.DelayAction
  alias JidoTest.TestActions.ErrorAction

  @moduletag :capture_log

  describe "run_async/4" do
    test "returns an async_ref with pid and ref" do
      result = Exec.run_async(BasicAction, %{value: 5})
      assert is_map(result)
      assert is_pid(result.pid)
      assert is_reference(result.ref)
    end
  end

  describe "await/2" do
    test "returns the result of a successful async action" do
      async_ref = Exec.run_async(BasicAction, %{value: 5}, %{}, timeout: 50)
      assert {:ok, %{value: 5}} = Exec.await(async_ref)
    end

    test "returns an error for a failed async action" do
      async_ref = Exec.run_async(ErrorAction, %{error_type: :runtime}, %{}, timeout: 50)

      assert {:error, error} = Exec.await(async_ref)
      assert is_exception(error)
      assert Exception.message(error) =~ "Runtime error"
    end

    test "returns a timeout error when the action exceeds the timeout" do
      async_ref = Exec.run_async(DelayAction, %{delay: 200}, %{}, timeout: 75)

      assert {:error,
              %Jido.Action.Error.TimeoutError{message: "Async action timed out after 50ms"}} =
               Exec.await(async_ref, 50)
    end
  end

  describe "cancel/1" do
    test "successfully cancels an async action" do
      async_ref = Exec.run_async(BasicAction, %{value: 5})
      assert :ok = Exec.cancel(async_ref)

      refute Process.alive?(async_ref.pid)
    end

    test "returns ok when cancelling an already completed action" do
      async_ref = Exec.run_async(BasicAction, %{value: 5}, %{}, timeout: 200)

      assert {:ok, %{value: 5}} = Exec.await(async_ref, 200)

      {cancel_us, cancel_result} = :timer.tc(fn -> Exec.cancel(async_ref) end)
      assert :ok = cancel_result
      assert cancel_us < 200_000
    end

    test "accepts a pid directly" do
      async_ref = Exec.run_async(BasicAction, %{value: 5})
      assert :ok = Exec.cancel(async_ref.pid)
      refute Process.alive?(async_ref.pid)
    end

    test "returns an error for invalid input" do
      assert {:error, %Jido.Action.Error.InvalidInputError{}} = Exec.cancel("invalid")
    end
  end

  test "integration of run_async, await, and cancel" do
    test_pid = self()
    async_ref = Exec.run_async(DelayAction, %{delay: 500}, %{}, timeout: 500)

    spawn(fn ->
      result = Exec.await(async_ref, 100)
      send(test_pid, {:await_result, result})

      Process.sleep(50)
      Exec.cancel(async_ref)

      receive do
        {:await_result, result} ->
          assert {:error, error} = result

          assert match?(%Jido.Action.Error.TimeoutError{}, error) or
                   match?(%Jido.Action.Error.ExecutionFailureError{}, error)

          assert Exception.message(error) =~ "Async action timed out after 100ms" or
                   Exception.message(error) =~ "Server error in async action: :shutdown"
      after
        2000 ->
          flunk("Await did not complete in time")
      end

      refute Process.alive?(async_ref.pid)
    end)
  end
end
