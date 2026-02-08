defmodule JidoTest.ExecFinalCoverageTest do
  @moduledoc """
  Final tests to push exec.ex coverage above 90%
  """

  use JidoTest.ActionCase, async: false
  use Mimic

  import ExUnit.CaptureLog

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

  describe "private function coverage" do
    test "test private helper functions through public interface" do
      # Test different error message types
      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(
                   CoverageTestActions.ErrorMessageTestAction,
                   %{error_type: :nil_message},
                   %{},
                   []
                 )
      end)

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(
                   CoverageTestActions.ErrorMessageTestAction,
                   %{error_type: :string_message},
                   %{},
                   []
                 )
      end)

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(
                   CoverageTestActions.ErrorMessageTestAction,
                   %{error_type: :struct_message},
                   %{},
                   []
                 )
      end)

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(
                   CoverageTestActions.ErrorMessageTestAction,
                   %{error_type: :nested_message},
                   %{},
                   []
                 )
      end)

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(
                   CoverageTestActions.ErrorMessageTestAction,
                   %{error_type: :no_message},
                   %{},
                   []
                 )
      end)
    end

    test "timeout handling with edge cases" do
      # Test timeout with exactly 0
      capture_log(fn ->
        assert {:ok, %{value: 1}} =
                 Exec.run(JidoTest.TestActions.BasicAction, %{value: 1}, %{}, timeout: 0)
      end)

      # Test timeout with negative value (should use default)
      capture_log(fn ->
        assert {:ok, %{value: 2}} =
                 Exec.run(JidoTest.TestActions.BasicAction, %{value: 2}, %{}, timeout: -1)
      end)

      # Test timeout with non-integer (should use default)
      capture_log(fn ->
        assert {:ok, %{value: 3}} =
                 Exec.run(JidoTest.TestActions.BasicAction, %{value: 3}, %{}, timeout: nil)
      end)
    end

    test "retry logic with different failure patterns" do
      # Test immediate success (no retries needed)
      capture_log(fn ->
        assert {:ok, %{result: "immediate"}} =
                 Exec.run(
                   CoverageTestActions.RetryPatternAction,
                   %{pattern: :immediate_success},
                   %{},
                   max_retries: 2
                 )
      end)
    end

    test "task group and process management edge cases" do
      capture_log(fn ->
        assert {:ok, %{spawned: true}} =
                 Exec.run(CoverageTestActions.TaskSpawningAction, %{}, %{}, timeout: 1000)
      end)
    end

    test "action result normalization edge cases" do
      # Test standard success
      capture_log(fn ->
        assert {:ok, %{standard: true}} =
                 Exec.run(
                   CoverageTestActions.ResultNormalizationAction,
                   %{result_type: :standard_ok},
                   %{},
                   []
                 )
      end)

      # Test three-tuple success
      capture_log(fn ->
        assert {:ok, %{three_tuple: true}, %{directive: "test"}} =
                 Exec.run(
                   CoverageTestActions.ResultNormalizationAction,
                   %{result_type: :three_tuple_ok},
                   %{},
                   []
                 )
      end)

      # Test three-tuple error
      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}, %{directive: "error"}} =
                 Exec.run(
                   CoverageTestActions.ResultNormalizationAction,
                   %{result_type: :three_tuple_error},
                   %{},
                   []
                 )
      end)

      # Test raw value (should fail with execution error)
      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{message: message}} =
                 Exec.run(
                   CoverageTestActions.ResultNormalizationAction,
                   %{result_type: :raw_value},
                   %{},
                   []
                 )

        assert message =~ "Unexpected return shape: %{raw: true}"
      end)
    end

    test "async execution edge case coverage" do
      # Test successful await
      capture_log(fn ->
        async_ref = Exec.run_async(DelayAction, %{delay: 50}, %{}, timeout: 200)
        assert {:ok, %{}} = Exec.await(async_ref, 300)
      end)

      # Test cancellation edge cases
      capture_log(fn ->
        async_ref = Exec.run_async(DelayAction, %{delay: 200}, %{}, timeout: 500)
        assert :ok = Exec.cancel(async_ref)
      end)
    end

    test "validation edge cases" do
      capture_log(fn ->
        assert {:ok, %{value: 42}} =
                 Exec.run(CoverageTestActions.NoValidateOutputAction, %{value: 42}, %{}, [])
      end)
    end

    test "compensation edge cases with timeout from opts" do
      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(CoverageTestActions.CompensationOptsAction, %{}, %{}, timeout: 50)
      end)
    end
  end

  describe "telemetry and monitoring coverage" do
    test "telemetry span execution" do
      # Test normal telemetry execution (not silent)
      capture_log(fn ->
        assert {:ok, %{value: 1}} =
                 Exec.run(JidoTest.TestActions.BasicAction, %{value: 1}, %{}, telemetry: :full)
      end)

      # Test silent telemetry
      capture_log(fn ->
        assert {:ok, %{value: 2}} =
                 Exec.run(JidoTest.TestActions.BasicAction, %{value: 2}, %{}, telemetry: :silent)
      end)
    end
  end

  describe "configuration function coverage" do
    test "configuration functions with different app env states" do
      original_env = Application.get_all_env(:jido_action)

      try do
        # Clear all environment
        for {key, _value} <- original_env do
          Application.delete_env(:jido_action, key)
        end

        # Test with missing config (should use defaults)
        capture_log(fn ->
          assert {:ok, %{value: 1}} =
                   Exec.run(JidoTest.TestActions.BasicAction, %{value: 1}, %{}, [])
        end)

        # Test async with default timeout
        capture_log(fn ->
          async_ref = Exec.run_async(JidoTest.TestActions.BasicAction, %{value: 2}, %{}, [])
          assert {:ok, %{value: 2}} = Exec.await(async_ref)
        end)
      after
        # Restore original environment
        for {key, value} <- original_env do
          Application.put_env(:jido_action, key, value)
        end
      end
    end
  end
end
