defmodule Jido.ExecTimeoutTaskSupervisorTest do
  use JidoTest.ActionCase, async: false

  # Import Private to access private functions for testing
  use Private

  import ExUnit.CaptureIO

  alias Jido.Action.Error
  alias Jido.Exec
  alias JidoTest.CoverageTestActions

  @moduletag :capture_log

  describe "Task.Supervisor async_nolink + yield/shutdown pattern" do
    test "action completes successfully before timeout" do
      result =
        Exec.execute_action_with_timeout(CoverageTestActions.FastAction, %{}, %{}, 1000,
          log_level: :info
        )

      assert {:ok, %{completed: true}} = result
    end

    test "action times out and returns timeout error" do
      result =
        Exec.execute_action_with_timeout(CoverageTestActions.SlowAction, %{}, %{}, 50,
          log_level: :info
        )

      assert {:error, %Error.TimeoutError{} = error} = result
      assert error.timeout == 50
      assert error.message =~ "timed out after 50ms"
      assert error.details[:action] == CoverageTestActions.SlowAction

      # Verify no stray messages in mailbox
      refute_receive _, 100
    end

    test "timeout error has concise message without params/context" do
      large_params = %{secret: "should_not_be_in_message", data: String.duplicate("x", 1000)}
      large_context = %{sensitive: "data", more: String.duplicate("y", 1000)}

      result =
        Exec.execute_action_with_timeout(
          CoverageTestActions.TimeoutMessageAction,
          large_params,
          large_context,
          50,
          log_level: :info
        )

      assert {:error, %Error.TimeoutError{} = error} = result

      # Message should be concise and not include params/context
      assert error.message =~ "timed out after 50ms"
      refute error.message =~ "should_not_be_in_message"
      refute error.message =~ "sensitive"

      # Details should only contain timeout and action (not full params/context)
      assert error.details[:timeout] == 50
      assert error.details[:action] == CoverageTestActions.TimeoutMessageAction
      refute Map.has_key?(error.details, :params)
      refute Map.has_key?(error.details, :context)
    end

    test "preserves group_leader for IO routing" do
      io =
        capture_io(fn ->
          result =
            Exec.execute_action_with_timeout(CoverageTestActions.IOActionCoverage, %{}, %{}, 1000,
              log_level: :info
            )

          assert {:ok, %{io_worked: true}} = result
        end)

      assert io =~ "test output"
    end

    test "child tasks are cleaned up on timeout with brutal_kill" do
      test_pid = self()

      # Execute the action with short timeout
      spawn_link(fn ->
        result =
          Exec.execute_action_with_timeout(
            CoverageTestActions.ChildSpawningAction,
            %{},
            %{test_pid: test_pid},
            50,
            log_level: :info
          )

        send(test_pid, {:result, result})
      end)

      # Get child PID
      child_pid =
        receive do
          {:parent_has_child, pid} -> pid
        after
          200 -> nil
        end

      # Wait for timeout result
      assert_receive {:result, {:error, %Error.TimeoutError{}}}, 500

      if child_pid do
        # Give Task.Supervisor time to kill processes
        Process.sleep(150)

        # Child should be terminated when parent is killed with :brutal_kill
        refute Process.alive?(child_pid),
               "Child process should be killed when parent times out"
      end
    end

    test "handles action that exits abnormally" do
      result =
        Exec.execute_action_with_timeout(CoverageTestActions.ExitingAction, %{}, %{}, 1000,
          log_level: :info
        )

      assert {:error, %Error.ExecutionFailureError{} = error} = result
      assert error.message =~ "Task exited"
    end

    test "handles action that is killed" do
      result =
        Exec.execute_action_with_timeout(
          CoverageTestActions.KillableActionSupervisor,
          %{},
          %{},
          1000,
          log_level: :info
        )

      assert {:error, %Error.ExecutionFailureError{} = error} = result
      assert error.message =~ "Task exited"
    end

    test "multiple concurrent timeouts don't interfere" do
      test_pid = self()

      # Spawn multiple actions concurrently
      for i <- 1..5 do
        spawn(fn ->
          result =
            Exec.execute_action_with_timeout(
              CoverageTestActions.ConcurrentAction,
              %{id: i, delay: i * 50},
              %{},
              75,
              log_level: :info
            )

          send(test_pid, {:result, i, result})
        end)
      end

      # Collect results
      results =
        for _ <- 1..5 do
          receive do
            {:result, id, result} -> {id, result}
          after
            2000 -> flunk("Did not receive all results")
          end
        end

      # Actions 1 should succeed, 2-5 should timeout
      results_map = Map.new(results)
      assert {:ok, %{id: 1}} = results_map[1]

      for i <- 2..5 do
        assert {:error, %Error.TimeoutError{}} = results_map[i]
      end
    end

    test "no process leaks after timeout" do
      task_supervisor = Jido.Action.TaskSupervisor
      initial_children = length(Task.Supervisor.children(task_supervisor))

      # Run several actions that timeout
      for _ <- 1..3 do
        Exec.execute_action_with_timeout(CoverageTestActions.LeakTestAction, %{}, %{}, 30,
          log_level: :info
        )
      end

      assert eventually_task_children_at_or_below?(task_supervisor, initial_children)
    end
  end

  defp eventually_task_children_at_or_below?(task_supervisor, limit, attempts \\ 20) do
    Enum.reduce_while(1..attempts, false, fn _, _acc ->
      current = length(Task.Supervisor.children(task_supervisor))

      if current <= limit do
        {:halt, true}
      else
        Process.sleep(25)
        {:cont, false}
      end
    end)
  end
end
