defmodule JidoTest.Exec.ClosureTest do
  use JidoTest.ActionCase, async: false

  import ExUnit.CaptureLog
  import Mock

  alias Jido.Action.Error
  alias Jido.Exec
  alias Jido.Exec.Closure
  alias JidoTest.TestActions.BasicAction
  alias JidoTest.TestActions.ContextAction
  alias JidoTest.TestActions.ErrorAction

  describe "closure/3" do
    test "creates a closure that can be called with params" do
      capture_log(fn ->
        closure = Closure.closure(BasicAction, %{})
        assert is_function(closure, 1)

        result = closure.(%{value: 5})
        assert {:ok, %{value: 5}} = result
      end)
    end

    test "closure preserves context and options" do
      with_mock Exec, run: fn _, _, _, _ -> {:ok, %{mocked: true}} end do
        closure = Closure.closure(ContextAction, %{context_key: "value"}, timeout: 5000)
        closure.(%{input: "test"})

        assert_called(
          Exec.run(ContextAction, %{input: "test"}, %{context_key: "value"}, timeout: 5000)
        )
      end
    end

    test "closure handles errors from the action" do
      capture_log(fn ->
        closure = Closure.closure(ErrorAction)

        assert {:error, %Error{type: :execution_error, message: message}} =
                 closure.(%{error_type: :runtime})

        assert message =~ "Runtime error"
      end)
    end

    test "closure validates params before execution" do
      # capture_log(fn ->
      closure = Closure.closure(BasicAction, %{})
      assert {:error, %Error{type: :validation_error}} = closure.(%{invalid: "params"})
      # end)
    end
  end

  describe "async_closure/3" do
    test "creates an async closure that returns an async_ref" do
      capture_log(fn ->
        async_closure = Closure.async_closure(BasicAction)
        assert is_function(async_closure, 1)

        async_ref = async_closure.(%{value: 10})
        assert is_map(async_ref)
        assert is_pid(async_ref.pid)
        assert is_reference(async_ref.ref)

        assert {:ok, %{value: 10}} = Exec.await(async_ref)
      end)
    end

    test "async_closure preserves context and options" do
      capture_log(fn ->
        with_mock Exec, run_async: fn _, _, _, _ -> %{ref: make_ref(), pid: self()} end do
          async_closure =
            Closure.async_closure(ContextAction, %{async_context: true}, timeout: 10_000)

          async_closure.(%{input: "async_test"})

          assert_called(
            Exec.run_async(ContextAction, %{input: "async_test"}, %{async_context: true},
              timeout: 10_000
            )
          )
        end
      end)
    end

    test "async_closure handles errors from the action" do
      capture_log(fn ->
        async_closure = Closure.async_closure(ErrorAction)
        async_ref = async_closure.(%{error_type: :runtime})

        assert {:error, %Error{type: :execution_error, message: message}} =
                 Exec.await(async_ref)

        assert message =~ "Runtime error"
      end)
    end
  end

  describe "error handling and edge cases" do
    test "closure handles invalid action" do
      assert_raise FunctionClauseError, fn ->
        Closure.closure("not_a_module")
      end
    end

    test "async_closure handles invalid action" do
      assert_raise FunctionClauseError, fn ->
        Closure.async_closure("not_a_module")
      end
    end

    test "closure with empty context and opts" do
      closure = Closure.closure(BasicAction)
      assert {:error, %Error{type: :validation_error}} = closure.(%{})
    end

    test "async_closure with empty context and opts" do
      async_closure = Closure.async_closure(BasicAction)
      async_ref = async_closure.(%{})
      assert {:error, %Error{type: :validation_error}} = Exec.await(async_ref)
    end
  end
end
