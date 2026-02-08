defmodule JidoTest.ExecReturnShapeTest do
  use JidoTest.ActionCase, async: false

  alias Jido.Action.Error
  alias Jido.Exec
  alias JidoTest.CoverageTestActions

  @moduletag :capture_log

  describe "strict return shape validation" do
    test "accepts {:ok, map} - happy path" do
      assert {:ok, %{result: "success"}} = Exec.run(CoverageTestActions.ValidOkAction, %{}, %{})
    end

    test "accepts {:ok, map, directive} - happy path with directive" do
      assert {:ok, %{result: "success"}, %{meta: "data"}} =
               Exec.run(CoverageTestActions.ValidOkWithDirectiveAction, %{}, %{})
    end

    test "accepts {:error, exception} - happy path error" do
      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(CoverageTestActions.ValidErrorAction, %{}, %{})
    end

    test "accepts {:error, exception, directive} - error with directive" do
      assert {:error, %Error.ExecutionFailureError{}, %{meta: "data"}} =
               Exec.run(CoverageTestActions.ValidErrorWithDirectiveAction, %{}, %{})
    end

    test "accepts {:error, string} and wraps in execution error" do
      assert {:error, %Error.ExecutionFailureError{message: "something went wrong"}} =
               Exec.run(CoverageTestActions.ValidErrorStringAction, %{}, %{})
    end

    test "rejects :ok atom - unexpected shape" do
      assert {:error, %Error.ExecutionFailureError{message: message}} =
               Exec.run(CoverageTestActions.AtomOkAction, %{}, %{})

      assert message =~ "Unexpected return shape: :ok"
    end

    test "rejects plain string - unexpected shape" do
      assert {:error, %Error.ExecutionFailureError{message: message}} =
               Exec.run(CoverageTestActions.StringResultAction, %{}, %{})

      assert message =~ ~s(Unexpected return shape: "result")
    end

    test "rejects plain map - unexpected shape" do
      assert {:error, %Error.ExecutionFailureError{message: message}} =
               Exec.run(CoverageTestActions.PlainMapAction, %{}, %{})

      assert message =~ "Unexpected return shape: %{"
      assert message =~ "foo: 1"
      assert message =~ "bar: 2"
    end

    test "rejects integer - unexpected shape" do
      assert {:error, %Error.ExecutionFailureError{message: message}} =
               Exec.run(CoverageTestActions.IntegerResultAction, %{}, %{})

      assert message =~ "Unexpected return shape: 42"
    end

    test "rejects list - unexpected shape" do
      assert {:error, %Error.ExecutionFailureError{message: message}} =
               Exec.run(CoverageTestActions.ListResultAction, %{}, %{})

      assert message =~ "Unexpected return shape: [1, 2, 3]"
    end

    test "unexpected return shape does not retry even when retries are configured" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      on_exit(fn ->
        if Process.alive?(counter), do: Agent.stop(counter)
      end)

      assert {:error, %Error.ExecutionFailureError{message: message}} =
               Exec.run(
                 CoverageTestActions.InvalidShapeCounterAction,
                 %{counter: counter},
                 %{},
                 max_retries: 3,
                 backoff: 1
               )

      assert message =~ "Unexpected return shape"
      assert Agent.get(counter, & &1) == 1
    end

    test "output validation only runs on {:ok, result} branch" do
      # Valid output passes validation
      assert {:ok, %{required_field: "valid"}} =
               Exec.run(
                 CoverageTestActions.OutputValidationAction,
                 %{return_type: :ok_valid},
                 %{}
               )

      # Invalid output fails validation
      assert {:error, %Error.InvalidInputError{}} =
               Exec.run(
                 CoverageTestActions.OutputValidationAction,
                 %{return_type: :ok_invalid},
                 %{}
               )

      # Raw map fails with execution error, not validation error
      assert {:error, %Error.ExecutionFailureError{message: message}} =
               Exec.run(
                 CoverageTestActions.OutputValidationAction,
                 %{return_type: :raw_map},
                 %{}
               )

      assert message =~ "Unexpected return shape"
      refute message =~ "validation"
    end

    test "error handling unchanged for {:error, reason}" do
      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(CoverageTestActions.ErrorHandlingAction, %{error_type: :execution}, %{})

      assert {:error, %Error.InvalidInputError{}} =
               Exec.run(
                 CoverageTestActions.ErrorHandlingAction,
                 %{error_type: :invalid_input},
                 %{}
               )

      assert {:error, %Error.TimeoutError{}} =
               Exec.run(CoverageTestActions.ErrorHandlingAction, %{error_type: :timeout}, %{})
    end
  end
end
