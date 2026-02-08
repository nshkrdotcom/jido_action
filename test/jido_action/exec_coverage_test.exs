defmodule JidoTest.ExecCoverageTest do
  @moduledoc """
  Additional tests to improve coverage of lib/jido_action/exec.ex
  Focuses on edge cases, error paths, and private functions not covered by existing tests.
  """

  use JidoTest.ActionCase, async: false
  use Mimic

  alias Jido.Action.Error
  alias Jido.Exec
  alias Jido.Exec.Validator
  alias JidoTest.CoverageTestActions
  alias JidoTest.TestActions.BasicAction
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

  defmodule ElsePathAction do
    @moduledoc false
    def validate_params(_params), do: {:error, :invalid_params}
    def run(params, _context), do: {:ok, params}
  end

  defmodule FunctionClauseMetadataAction do
    @moduledoc false
    def validate_params(params), do: {:ok, params}
    def run(params, _context), do: {:ok, params}

    def __action_metadata__ do
      raise FunctionClauseError, module: __MODULE__, function: :metadata, arity: 1
    end
  end

  defmodule RuntimeMetadataAction do
    @moduledoc false
    def validate_params(params), do: {:ok, params}
    def run(params, _context), do: {:ok, params}
    def __action_metadata__, do: raise("metadata boom")
  end

  defmodule ThrowMetadataAction do
    @moduledoc false
    def validate_params(params), do: {:ok, params}
    def run(params, _context), do: {:ok, params}
    def __action_metadata__, do: throw(:metadata_boom)
  end

  describe "run/4 defensive paths" do
    test "normalizes validator errors through with/else branch" do
      assert {:error, %Error.InvalidInputError{}} =
               Exec.run(ElsePathAction, %{value: 1}, %{}, log_level: :debug)
    end

    test "returns validation error for function clause metadata failures" do
      assert {:error, %Error.InvalidInputError{message: message}} =
               Exec.run(FunctionClauseMetadataAction, %{value: 1}, %{}, log_level: :debug)

      assert message =~ "Invalid action module"
    end

    test "returns internal error for unexpected metadata exceptions" do
      assert {:error, %Error.InternalError{message: message}} =
               Exec.run(RuntimeMetadataAction, %{value: 1}, %{}, log_level: :debug)

      assert message =~ "An unexpected error occurred"
    end

    test "returns internal error for thrown metadata failures" do
      assert {:error, %Error.InternalError{message: message}} =
               Exec.run(ThrowMetadataAction, %{value: 1}, %{}, log_level: :debug)

      assert message =~ "Caught throw"
    end
  end

  describe "configuration functions coverage" do
    test "get_default_timeout uses application config" do
      original_timeout = Application.get_env(:jido_action, :default_timeout)

      try do
        Application.put_env(:jido_action, :default_timeout, 200)

        # Test that async await uses the configured timeout when no explicit timeout is provided
        async_ref = Exec.run_async(DelayAction, %{delay: 500}, %{}, [])

        start_time = System.monotonic_time(:millisecond)
        assert {:error, %Error.TimeoutError{}} = Exec.await(async_ref)
        end_time = System.monotonic_time(:millisecond)

        # Should timeout around the configured 200ms
        assert end_time - start_time >= 150 and end_time - start_time <= 400
      after
        if original_timeout do
          Application.put_env(:jido_action, :default_timeout, original_timeout)
        else
          Application.delete_env(:jido_action, :default_timeout)
        end
      end
    end

    test "get_default_max_retries uses application config" do
      original_max_retries = Application.get_env(:jido_action, :default_max_retries)

      try do
        Application.put_env(:jido_action, :default_max_retries, 3)

        # Create a simple action that tracks retry attempts
        defmodule RetryTestAction do
          use Jido.Action,
            name: "retry_test",
            description: "Test action for retry logic"

          def run(_params, context) do
            current_count = Agent.get_and_update(context.counter_agent, &{&1, &1 + 1})

            if current_count < 3 do
              {:error, Error.execution_error("Retry attempt #{current_count + 1}")}
            else
              {:ok, %{attempt: current_count + 1}}
            end
          end
        end

        {:ok, counter_agent} = Agent.start_link(fn -> 0 end)

        # Should retry 3 times (default from config) and succeed on 4th attempt
        assert {:ok, %{attempt: 4}} =
                 Exec.run(RetryTestAction, %{}, %{counter_agent: counter_agent}, backoff: 10)

        Agent.stop(counter_agent)
      after
        if original_max_retries do
          Application.put_env(:jido_action, :default_max_retries, original_max_retries)
        else
          Application.delete_env(:jido_action, :default_max_retries)
        end
      end
    end

    test "get_default_backoff uses application config" do
      original_backoff = Application.get_env(:jido_action, :default_backoff)

      try do
        Application.put_env(:jido_action, :default_backoff, 10)

        # Create a simple action that tracks retry attempts and timing
        defmodule BackoffTestAction do
          use Jido.Action,
            name: "backoff_test",
            description: "Test action for backoff timing"

          def run(_params, context) do
            current_count = Agent.get_and_update(context.counter_agent, &{&1, &1 + 1})
            Agent.update(context.time_agent, &[System.monotonic_time(:millisecond) | &1])

            if current_count < 2 do
              {:error, Error.execution_error("Backoff test #{current_count + 1}")}
            else
              {:ok, %{attempt: current_count + 1}}
            end
          end
        end

        {:ok, counter_agent} = Agent.start_link(fn -> 0 end)
        {:ok, time_agent} = Agent.start_link(fn -> [] end)

        assert {:ok, %{attempt: 3}} =
                 Exec.run(
                   BackoffTestAction,
                   %{},
                   %{counter_agent: counter_agent, time_agent: time_agent},
                   max_retries: 2,
                   backoff: 10
                 )

        times = Agent.get(time_agent, &Enum.reverse/1)

        # Check that there was appropriate backoff between attempts
        if length(times) >= 2 do
          diff1 = Enum.at(times, 1) - Enum.at(times, 0)
          # Should be around 10ms for first retry
          assert diff1 >= 8

          if length(times) >= 3 do
            diff2 = Enum.at(times, 2) - Enum.at(times, 1)
            # Should be around 20ms for second retry (doubled backoff)
            assert diff2 >= 15
          end
        end

        Agent.stop(counter_agent)
        Agent.stop(time_agent)
      after
        if original_backoff do
          Application.put_env(:jido_action, :default_backoff, original_backoff)
        else
          Application.delete_env(:jido_action, :default_backoff)
        end
      end
    end
  end

  describe "Instruction struct execution coverage" do
    test "run/1 with Instruction struct" do
      instruction = %Jido.Instruction{
        action: BasicAction,
        params: %{value: 42},
        context: %{test: "context"},
        opts: [timeout: 1000, log_level: :debug]
      }

      assert {:ok, %{value: 42}} = Exec.run(instruction)
    end

    test "run/1 with Instruction struct using all defaults" do
      instruction = %Jido.Instruction{
        action: BasicAction,
        params: %{value: 100},
        context: %{},
        opts: []
      }

      assert {:ok, %{value: 100}} = Exec.run(instruction)
    end
  end

  describe "error handling edge cases" do
    test "run/4 with non-atom action" do
      assert {:error, %Error.InvalidInputError{}} =
               Exec.run("not_an_atom", %{}, %{}, [])
    end

    test "run/4 with non-list opts" do
      assert {:error, %Error.InvalidInputError{}} =
               Exec.run(CoverageTestActions.TestAction, %{value: 1}, %{}, %{not: "list"})
    end

    test "normalize_params with exception struct" do
      error = Error.validation_error("test error")
      assert {:error, ^error} = Exec.normalize_params(error)
    end

    test "normalize_params with various invalid types" do
      assert {:error, %Error.InvalidInputError{}} = Exec.normalize_params(:invalid_atom)
      assert {:error, %Error.InvalidInputError{}} = Exec.normalize_params(123)
      assert {:error, %Error.InvalidInputError{}} = Exec.normalize_params({:something, "else"})
    end

    test "normalize_context with various invalid types" do
      assert {:error, %Error.InvalidInputError{}} = Exec.normalize_context(:invalid_atom)
      assert {:error, %Error.InvalidInputError{}} = Exec.normalize_context(123)
      assert {:error, %Error.InvalidInputError{}} = Exec.normalize_context("invalid_string")
    end

    test "validate_action with module compilation failure" do
      assert {:error, %Error.InvalidInputError{}} =
               Validator.validate_action(NonExistentModule)
    end

    test "validate_action with module missing run/2" do
      assert {:error, %Error.InvalidInputError{}} =
               Validator.validate_action(CoverageTestActions.NoRunModule)
    end

    test "validate_params with action missing validate_params/1" do
      assert {:error, %Error.InvalidInputError{}} =
               Validator.validate_params(CoverageTestActions.NoValidateParamsModule, %{})
    end

    test "validate_params with invalid return from validate_params/1" do
      assert {:error, %Error.InvalidInputError{}} =
               Validator.validate_params(CoverageTestActions.InvalidValidateReturnModule, %{})
    end
  end

  describe "execution timeout edge cases" do
    test "execute_action_with_timeout with zero timeout" do
      original_timeout_zero_mode = Application.get_env(:jido_action, :timeout_zero_mode)

      on_exit(fn ->
        if is_nil(original_timeout_zero_mode) do
          Application.delete_env(:jido_action, :timeout_zero_mode)
        else
          Application.put_env(:jido_action, :timeout_zero_mode, original_timeout_zero_mode)
        end
      end)

      Application.put_env(:jido_action, :timeout_zero_mode, :immediate_timeout)

      assert {:error, %Error.TimeoutError{timeout: 0}} =
               Exec.run(BasicAction, %{value: 1}, %{}, timeout: 0)
    end

    test "execute_action_with_timeout with invalid timeout value" do
      assert {:ok, %{value: 1}} =
               Exec.run(BasicAction, %{value: 1}, %{}, timeout: -100)
    end

    test "execute_action_with_timeout with non-integer timeout" do
      assert {:ok, %{value: 1}} =
               Exec.run(BasicAction, %{value: 1}, %{}, timeout: 100.5)
    end
  end

  describe "output validation coverage" do
    test "validate_output with action missing validate_output/1" do
      assert {:ok, %{value: 1}} = Exec.run(BasicAction, %{value: 1}, %{}, [])
    end

    test "validate_output with invalid return from validate_output/1" do
      assert {:ok, %{value: 1}} =
               Exec.run(CoverageTestActions.ValidOutputValidationAction, %{value: 1}, %{}, [])
    end

    test "action returning non-standard result fails with execution error" do
      assert {:error, %Error.ExecutionFailureError{message: message}} =
               Exec.run(CoverageTestActions.NonStandardResultAction, %{value: 1}, %{}, [])

      assert message =~ "Unexpected return shape: %{value: 1}"
    end
  end

  describe "cancel edge cases" do
    test "cancel with map containing only pid key" do
      async_ref = Exec.run_async(BasicAction, %{value: 5})

      assert :ok = Exec.cancel(%{pid: async_ref.pid})
    end

    test "cancel with invalid async_ref types" do
      assert {:error, %Error.InvalidInputError{}} = Exec.cancel(nil)
      assert {:error, %Error.InvalidInputError{}} = Exec.cancel([])
      assert {:error, %Error.InvalidInputError{}} = Exec.cancel(%{invalid: "ref"})
    end
  end

  describe "async edge cases" do
    test "await handles DOWN message for normal process exit with delayed result" do
      parent = self()
      ref = make_ref()

      {:ok, pid} =
        Task.start(fn ->
          Process.sleep(50)
          send(parent, {:action_async_result, ref, {:ok, %{delayed: true}}})
        end)

      Process.monitor(pid)
      async_ref = %{ref: ref, pid: pid}

      Process.sleep(100)

      assert {:ok, %{delayed: true}} = Exec.await(async_ref, 200)
    end

    test "await handles DOWN message for crashed process" do
      _parent = self()
      ref = make_ref()

      {:ok, pid} =
        Task.start(fn ->
          Process.sleep(20)
          raise "simulated crash"
        end)

      Process.monitor(pid)
      async_ref = %{ref: ref, pid: pid}

      assert {:error, %Error.ExecutionFailureError{}} = Exec.await(async_ref, 1000)
    end
  end

  describe "exception handling in run/4" do
    test "handles various runtime errors" do
      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(CoverageTestActions.BadArityAction, %{cause_error: true}, %{}, [])
    end

    test "handles catch with throw" do
      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(CoverageTestActions.ThrowAction, %{cause_throw: true}, %{}, [])
    end

    test "handles catch with exit" do
      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(CoverageTestActions.ExitAction, %{cause_exit: true}, %{}, [])
    end
  end

  describe "extract_safe_error_message coverage" do
    test "extracts message from nested error structures" do
      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(CoverageTestActions.NestedErrorAction, %{}, %{}, [])
    end

    test "handles error with nil message" do
      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(CoverageTestActions.NilMessageErrorAction, %{}, %{}, [])
    end

    test "handles error with struct message" do
      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(CoverageTestActions.StructMessageErrorAction, %{}, %{}, [])
    end

    test "handles error with struct message without message field" do
      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(CoverageTestActions.StructNoMessageAction, %{}, %{}, [])
    end
  end

  describe "telemetry options coverage" do
    test "silent telemetry option" do
      assert {:ok, %{value: 1}} =
               Exec.run(BasicAction, %{value: 1}, %{}, telemetry: :silent)
    end
  end

  describe "task cleanup coverage" do
    test "Task.Supervisor handles task shutdown on timeout" do
      async_ref = Exec.run_async(DelayAction, %{delay: 500}, %{}, timeout: 100)

      assert {:error, %Error.TimeoutError{}} = Exec.await(async_ref, 150)
    end
  end

  describe "calculate_backoff edge cases" do
    @tag timeout: 5000
    test "backoff calculation with moderate retry count" do
      defmodule ModerateRetryAction do
        use Jido.Action,
          name: "moderate_retry",
          description: "Action for testing moderate retry counts"

        def run(_params, context) do
          current_count = Agent.get_and_update(context.counter_agent, &{&1, &1 + 1})

          if current_count < 3 do
            {:error, Error.execution_error("Retry #{current_count + 1}")}
          else
            {:ok, %{attempt: current_count + 1}}
          end
        end
      end

      {:ok, counter_agent} = Agent.start_link(fn -> 0 end)

      assert {:ok, %{attempt: 4}} =
               Exec.run(ModerateRetryAction, %{}, %{counter_agent: counter_agent},
                 max_retries: 3,
                 backoff: 10
               )

      Agent.stop(counter_agent)
    end
  end
end
