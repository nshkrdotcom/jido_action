defmodule JidoTest.ExecEdgeCasesTest do
  @moduledoc """
  Additional edge case tests to achieve >90% coverage for lib/jido_action/exec.ex
  """

  use JidoTest.ActionCase, async: false
  use Mimic

  alias Jido.Action.Error
  alias Jido.Exec
  alias JidoTest.CoverageTestActions
  alias JidoTest.TestActions.DelayAction

  @moduletag :capture_log

  setup :set_mimic_global

  setup do
    Logger.put_process_level(self(), :debug)

    on_exit(fn ->
      Logger.delete_process_level(self())
    end)

    :ok
  end

  describe "compensation edge cases" do
    test "handles compensation with timeout configuration from metadata" do
      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(CoverageTestActions.CompensationTimeoutAction, %{}, %{}, [])
    end

    test "handles compensation with error result" do
      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(CoverageTestActions.FailingCompensationAction, %{}, %{}, [])
    end

    test "handles compensation with invalid result" do
      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(CoverageTestActions.InvalidCompensationResultAction, %{}, %{}, [])
    end

    test "compensation with special result fields" do
      assert {:error, %Error.ExecutionFailureError{details: details}} =
               Exec.run(CoverageTestActions.SpecialFieldsCompensationAction, %{}, %{}, [])

      assert details.compensation_result == %{
               test_value: "special",
               compensation_context: %{data: "context"},
               other_field: "normal"
             }
    end
  end

  describe "error handling edge cases with directives" do
    test "handles errors with directive tuples" do
      assert {:error, %Error.ExecutionFailureError{}, directive} =
               Exec.run(CoverageTestActions.DirectiveErrorAction, %{}, %{}, [])

      assert directive.type == "test_directive"
    end

    test "handles compensation timeout with directive" do
      assert {:error, %Error.ExecutionFailureError{}, directive} =
               Exec.run(CoverageTestActions.CompensationTimeoutDirectiveAction, %{}, %{}, [])

      assert directive.type == "timeout_directive"
    end
  end

  describe "task execution edge cases" do
    test "handles killed task in timeout execution" do
      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(CoverageTestActions.KillableAction, %{}, %{}, timeout: 1000)
    end

    test "handles task exit with reason" do
      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(CoverageTestActions.ExitingTaskAction, %{}, %{}, timeout: 1000)
    end

    test "handles task cleanup on timeout" do
      # This test exercises Task.Supervisor cleanup on timeout
      # Start a long-running action that will timeout and trigger cleanup
      assert {:error, %Error.TimeoutError{}} =
               Exec.run(DelayAction, %{delay: 500}, %{}, timeout: 100, max_retries: 0)
    end
  end

  describe "action result edge cases" do
    test "handles action returning 3-tuple success with directive" do
      assert {:ok, %{value: 42}, directive} =
               Exec.run(CoverageTestActions.ThreeTupleSuccessAction, %{value: 42}, %{}, [])

      assert directive.type == "success_directive"
    end

    test "handles action output validation with 3-tuple" do
      assert {:ok, %{value: 1}, directive} =
               Exec.run(CoverageTestActions.ThreeTupleValidationAction, %{value: 1}, %{}, [])

      assert directive.type == "validation_directive"
    end

    test "handles action 3-tuple success results" do
      assert {:ok, %{value: 1}, directive} =
               Exec.run(CoverageTestActions.Simple3TupleAction, %{value: 1}, %{}, [])

      assert directive.type == "simple_directive"
    end
  end

  describe "exception handling in execute_action" do
    test "handles RuntimeError in action execution" do
      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(CoverageTestActions.RuntimeErrorAction, %{}, %{}, [])
    end

    test "handles ArgumentError in action execution" do
      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(CoverageTestActions.ArgumentErrorAction, %{}, %{}, [])
    end

    test "handles other exceptions in action execution" do
      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(CoverageTestActions.OtherExceptionAction, %{}, %{}, [])
    end
  end

  describe "additional normalization edge cases" do
    test "normalize_params with nested {:ok, {:ok, params}}" do
      # Test nested ok tuples
      nested_ok = {:ok, {:ok, %{key: "value"}}}
      assert {:error, %Error.InvalidInputError{}} = Exec.normalize_params(nested_ok)
    end

    test "normalize_params with complex nested error" do
      nested_error = {:error, {:nested, "error"}}
      assert {:error, %Error.InvalidInputError{}} = Exec.normalize_params(nested_error)
    end
  end
end
