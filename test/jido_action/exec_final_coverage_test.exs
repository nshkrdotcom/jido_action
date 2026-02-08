defmodule JidoTest.ExecFinalCoverageTest do
  @moduledoc """
  Final tests to push exec.ex coverage above 90%
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

  describe "private function coverage" do
    test "test private helper functions through public interface" do
      # Test different error message types
      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(
                 CoverageTestActions.ErrorMessageTestAction,
                 %{error_type: :nil_message},
                 %{},
                 []
               )

      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(
                 CoverageTestActions.ErrorMessageTestAction,
                 %{error_type: :string_message},
                 %{},
                 []
               )

      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(
                 CoverageTestActions.ErrorMessageTestAction,
                 %{error_type: :struct_message},
                 %{},
                 []
               )

      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(
                 CoverageTestActions.ErrorMessageTestAction,
                 %{error_type: :nested_message},
                 %{},
                 []
               )

      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(
                 CoverageTestActions.ErrorMessageTestAction,
                 %{error_type: :no_message},
                 %{},
                 []
               )
    end

    test "timeout handling with edge cases" do
      # Test timeout with exactly 0 (immediate timeout)
      assert {:error, %Error.TimeoutError{timeout: 0}} =
               Exec.run(JidoTest.TestActions.BasicAction, %{value: 1}, %{}, timeout: 0)

      # Test timeout with negative value (should use default)
      assert {:ok, %{value: 2}} =
               Exec.run(JidoTest.TestActions.BasicAction, %{value: 2}, %{}, timeout: -1)

      # Test timeout with non-integer (should use default)
      assert {:ok, %{value: 3}} =
               Exec.run(JidoTest.TestActions.BasicAction, %{value: 3}, %{}, timeout: nil)
    end

    test "retry logic with different failure patterns" do
      # Test immediate success (no retries needed)
      assert {:ok, %{result: "immediate"}} =
               Exec.run(
                 CoverageTestActions.RetryPatternAction,
                 %{pattern: :immediate_success},
                 %{},
                 max_retries: 2
               )
    end

    test "task group and process management edge cases" do
      assert {:ok, %{spawned: true}} =
               Exec.run(CoverageTestActions.TaskSpawningAction, %{}, %{}, timeout: 1000)
    end

    test "action result normalization edge cases" do
      # Test standard success
      assert {:ok, %{standard: true}} =
               Exec.run(
                 CoverageTestActions.ResultNormalizationAction,
                 %{result_type: :standard_ok},
                 %{},
                 []
               )

      # Test three-tuple success
      assert {:ok, %{three_tuple: true}, %{directive: "test"}} =
               Exec.run(
                 CoverageTestActions.ResultNormalizationAction,
                 %{result_type: :three_tuple_ok},
                 %{},
                 []
               )

      # Test three-tuple error
      assert {:error, %Error.ExecutionFailureError{}, %{directive: "error"}} =
               Exec.run(
                 CoverageTestActions.ResultNormalizationAction,
                 %{result_type: :three_tuple_error},
                 %{},
                 []
               )

      # Test raw value (should fail with execution error)
      assert {:error, %Error.ExecutionFailureError{message: message}} =
               Exec.run(
                 CoverageTestActions.ResultNormalizationAction,
                 %{result_type: :raw_value},
                 %{},
                 []
               )

      assert message =~ "Unexpected return shape: %{raw: true}"
    end

    test "async execution edge case coverage" do
      # Test successful await
      async_ref = Exec.run_async(DelayAction, %{delay: 50}, %{}, timeout: 200)
      assert {:ok, %{}} = Exec.await(async_ref, 300)

      # Test cancellation edge cases
      async_ref = Exec.run_async(DelayAction, %{delay: 200}, %{}, timeout: 500)
      assert :ok = Exec.cancel(async_ref)
    end

    test "validation edge cases" do
      assert {:ok, %{value: 42}} =
               Exec.run(CoverageTestActions.NoValidateOutputAction, %{value: 42}, %{}, [])
    end

    test "compensation edge cases with timeout from opts" do
      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(CoverageTestActions.CompensationOptsAction, %{}, %{}, timeout: 50)
    end
  end

  describe "telemetry and monitoring coverage" do
    test "telemetry span execution" do
      # Test normal telemetry execution (not silent)
      assert {:ok, %{value: 1}} =
               Exec.run(JidoTest.TestActions.BasicAction, %{value: 1}, %{}, telemetry: :full)

      # Test silent telemetry
      assert {:ok, %{value: 2}} =
               Exec.run(JidoTest.TestActions.BasicAction, %{value: 2}, %{}, telemetry: :silent)
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
        assert {:ok, %{value: 1}} =
                 Exec.run(JidoTest.TestActions.BasicAction, %{value: 1}, %{}, [])

        # Test async with default timeout
        async_ref = Exec.run_async(JidoTest.TestActions.BasicAction, %{value: 2}, %{}, [])
        assert {:ok, %{value: 2}} = Exec.await(async_ref)
      after
        # Restore original environment
        for {key, value} <- original_env do
          Application.put_env(:jido_action, key, value)
        end
      end
    end
  end
end
