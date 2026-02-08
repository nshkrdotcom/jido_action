defmodule JidoTest.ExecMiscCoverageTest do
  @moduledoc """
  Tests for miscellaneous uncovered lines in exec.ex
  """

  use JidoTest.ActionCase, async: false

  import ExUnit.CaptureLog

  alias Jido.Action.Error
  alias Jido.Exec
  alias JidoTest.CoverageTestActions

  @moduletag :capture_log

  describe "miscellaneous coverage" do
    test "handle various error message extraction scenarios" do
      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(CoverageTestActions.StructMessageAction, %{}, %{})
      end)
    end

    test "await with process exit scenarios" do
      # Test the edge case where a process exits normally but we receive the result
      capture_log(fn ->
        parent = self()
        ref = make_ref()

        # Create a task that exits normally but sends result first
        {:ok, pid} =
          Task.start_link(fn ->
            send(parent, {:action_async_result, ref, {:ok, %{delayed: true}}})
            # Exit normally
            :ok
          end)

        # Monitor the process
        Process.monitor(pid)
        async_ref = %{ref: ref, pid: pid}

        # Wait for the result - this should handle the normal exit case
        result = Exec.await(async_ref, 1000)
        assert {:ok, %{delayed: true}} = result
      end)
    end

    test "normalize params with various invalid structures" do
      # Test edge cases in param normalization
      assert {:error, %Error.InvalidInputError{}} = Exec.normalize_params(fn -> :function end)
      assert {:error, %Error.InvalidInputError{}} = Exec.normalize_params(self())
      assert {:error, %Error.InvalidInputError{}} = Exec.normalize_params(make_ref())
    end

    test "compensation with specific timeout configurations" do
      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(CoverageTestActions.SpecificTimeoutCompAction, %{}, %{})
      end)
    end

    test "task cleanup and process group management" do
      capture_log(fn ->
        assert {:error, %Error.TimeoutError{}} =
                 Exec.run(CoverageTestActions.CleanupTestAction, %{}, %{}, timeout: 30)
      end)
    end

    test "additional error handling paths" do
      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(CoverageTestActions.CatchTestAction, %{error_type: :throw}, %{},
                   timeout: 1000
                 )
      end)

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(CoverageTestActions.CatchTestAction, %{error_type: :exit}, %{},
                   timeout: 1000
                 )
      end)
    end

    test "backoff calculation edge cases" do
      capture_log(fn ->
        result =
          Exec.run(CoverageTestActions.SmallBackoffAction, %{succeed: true}, %{},
            max_retries: 2,
            backoff: 10
          )

        assert {:ok, %{succeeded: true}} = result
      end)
    end
  end
end
