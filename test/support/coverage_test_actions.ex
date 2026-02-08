# credo:disable-for-this-file Credo.Check.Readability.ModuleDoc

defmodule JidoTest.CoverageTestActions do
  @moduledoc """
  Test action modules used by coverage tests.
  Pre-compiled here to avoid per-test inline compilation overhead (~250ms each).
  """

  alias Jido.Action
  alias Jido.Action.Error

  # ── exec_return_shape_test.exs ──

  defmodule ValidOkAction do
    use Action, name: "valid_ok"
    def run(_params, _context), do: {:ok, %{result: "success"}}
  end

  defmodule ValidOkWithDirectiveAction do
    use Action, name: "valid_ok_directive"
    def run(_params, _context), do: {:ok, %{result: "success"}, %{meta: "data"}}
  end

  defmodule ValidErrorAction do
    use Action, name: "valid_error"
    def run(_params, _context), do: {:error, Error.execution_error("failed")}
  end

  defmodule ValidErrorWithDirectiveAction do
    use Action, name: "valid_error_directive"
    def run(_params, _context), do: {:error, Error.execution_error("failed"), %{meta: "data"}}
  end

  defmodule ValidErrorStringAction do
    use Action, name: "valid_error_string"
    def run(_params, _context), do: {:error, "something went wrong"}
  end

  defmodule AtomOkAction do
    use Action, name: "atom_ok"
    @dialyzer {:nowarn_function, run: 2}
    def run(_params, _context), do: :ok
  end

  defmodule StringResultAction do
    use Action, name: "string_result"
    @dialyzer {:nowarn_function, run: 2}
    def run(_params, _context), do: "result"
  end

  defmodule PlainMapAction do
    use Action, name: "plain_map"
    @dialyzer {:nowarn_function, run: 2}
    def run(_params, _context), do: %{foo: 1, bar: 2}
  end

  defmodule IntegerResultAction do
    use Action, name: "integer_result"
    @dialyzer {:nowarn_function, run: 2}
    def run(_params, _context), do: 42
  end

  defmodule ListResultAction do
    use Action, name: "list_result"
    @dialyzer {:nowarn_function, run: 2}
    def run(_params, _context), do: [1, 2, 3]
  end

  defmodule InvalidShapeCounterAction do
    use Action,
      name: "invalid_shape_counter_action",
      schema: [
        counter: [type: :any, required: true]
      ]

    @dialyzer {:nowarn_function, run: 2}
    def run(%{counter: counter}, _context) do
      Agent.update(counter, &(&1 + 1))
      :invalid_shape
    end
  end

  defmodule OutputValidationAction do
    use Action,
      name: "output_validation",
      output_schema: [
        required_field: [type: :string, required: true]
      ]

    def run(%{return_type: :ok_valid}, _context), do: {:ok, %{required_field: "valid"}}
    def run(%{return_type: :ok_invalid}, _context), do: {:ok, %{wrong_field: "invalid"}}
    def run(%{return_type: :raw_map}, _context), do: %{required_field: "this won't be validated"}
  end

  defmodule ErrorHandlingAction do
    use Action, name: "error_handling"

    def run(%{error_type: :execution}, _context),
      do: {:error, Error.execution_error("execution failed")}

    def run(%{error_type: :invalid_input}, _context),
      do: {:error, Error.validation_error("validation failed")}

    def run(%{error_type: :timeout}, _context),
      do: {:error, Error.timeout_error("timeout")}
  end

  # ── exec_edge_cases_test.exs ──

  defmodule CompensationTimeoutAction do
    use Action,
      name: "compensation_timeout_action",
      description: "Action with compensation timeout config",
      compensation: [enabled: true, timeout: 200]

    def run(_params, _context), do: {:error, Error.execution_error("test error")}

    def on_error(_params, _error, _context, _opts) do
      Process.sleep(30)
      {:ok, %{compensated: true}}
    end
  end

  defmodule FailingCompensationAction do
    use Action,
      name: "failing_compensation",
      description: "Action with failing compensation",
      compensation: [enabled: true]

    def run(_params, _context), do: {:error, Error.execution_error("original error")}
    def on_error(_params, _error, _context, _opts), do: {:error, "compensation failed"}
  end

  defmodule InvalidCompensationResultAction do
    use Action,
      name: "invalid_compensation_result",
      description: "Action with invalid compensation result",
      compensation: [enabled: true]

    def run(_params, _context), do: {:error, Error.execution_error("original error")}
    def on_error(_params, _error, _context, _opts), do: :invalid_result
  end

  defmodule SpecialFieldsCompensationAction do
    use Action,
      name: "special_fields_compensation",
      description: "Action with special compensation fields",
      compensation: [enabled: true]

    def run(_params, _context), do: {:error, Error.execution_error("original error")}

    def on_error(_params, _error, _context, _opts) do
      {:ok,
       %{
         test_value: "special",
         compensation_context: %{data: "context"},
         other_field: "normal"
       }}
    end
  end

  defmodule DirectiveErrorAction do
    use Action,
      name: "directive_error",
      description: "Action that returns error with directive"

    def run(_params, _context) do
      directive = %{type: "test_directive", data: "test"}
      {:error, Error.execution_error("error with directive"), directive}
    end
  end

  defmodule CompensationTimeoutDirectiveAction do
    use Action,
      name: "compensation_timeout_directive",
      description: "Action with compensation timeout and directive",
      compensation: [enabled: true, timeout: 30]

    def run(_params, _context) do
      directive = %{type: "timeout_directive"}
      {:error, Error.execution_error("error"), directive}
    end

    def on_error(_params, _error, _context, _opts) do
      Process.sleep(60)
      {:ok, %{compensated: true}}
    end
  end

  defmodule KillableAction do
    use Action,
      name: "killable",
      description: "Action that can be killed"

    def run(_params, _context) do
      Process.exit(self(), :kill)
      {:ok, %{}}
    end
  end

  defmodule ExitingTaskAction do
    use Action,
      name: "exiting_task",
      description: "Action that exits with reason"

    def run(_params, _context) do
      Process.exit(self(), {:shutdown, :custom_reason})
      {:ok, %{}}
    end
  end

  defmodule ThreeTupleSuccessAction do
    use Action,
      name: "three_tuple_success",
      description: "Action returning 3-tuple success"

    def run(params, _context) do
      directive = %{type: "success_directive", data: "test"}
      {:ok, params, directive}
    end
  end

  defmodule ThreeTupleValidationAction do
    use Action,
      name: "three_tuple_validation",
      description: "Action with 3-tuple and validation"

    def run(params, _context) do
      directive = %{type: "validation_directive"}
      {:ok, params, directive}
    end
  end

  defmodule Simple3TupleAction do
    use Action,
      name: "simple_three_tuple",
      description: "Action with simple 3-tuple result"

    def run(params, _context) do
      directive = %{type: "simple_directive"}
      {:ok, params, directive}
    end
  end

  defmodule RuntimeErrorAction do
    use Action,
      name: "runtime_error",
      description: "Action that raises RuntimeError"

    def run(_params, _context), do: raise("runtime error occurred")
  end

  defmodule ArgumentErrorAction do
    use Action,
      name: "argument_error",
      description: "Action that raises ArgumentError"

    def run(_params, _context), do: raise(ArgumentError, "invalid argument")
  end

  defmodule OtherExceptionAction do
    use Action,
      name: "other_exception",
      description: "Action that raises other exception"

    def run(_params, _context), do: raise(KeyError, "key not found")
  end

  # ── exec_coverage_test.exs ──

  defmodule TestAction do
    use Action, name: "test", description: "test"
    def run(params, _context), do: {:ok, params}
  end

  defmodule NoRunModule do
    @moduledoc false
    def validate_params(_), do: {:ok, %{}}
  end

  defmodule NoValidateParamsModule do
    @moduledoc false
    def run(_params, _context), do: {:ok, %{}}
  end

  defmodule InvalidValidateReturnModule do
    @moduledoc false
    def run(_params, _context), do: {:ok, %{}}
    def validate_params(_params), do: :invalid_return
  end

  defmodule ValidOutputValidationAction do
    use Action,
      name: "valid_output_validation",
      description: "Action with valid output validation"

    def run(params, _context), do: {:ok, params}
  end

  defmodule NonStandardResultAction do
    use Action,
      name: "non_standard_result",
      description: "Action returning non-standard result"

    def run(params, _context), do: params
  end

  defmodule NestedErrorAction do
    use Action,
      name: "nested_error",
      description: "Action with nested error message"

    def run(_params, _context) do
      {:error, %{message: %{message: "deeply nested message"}}}
    end
  end

  defmodule NilMessageErrorAction do
    use Action,
      name: "nil_message_error",
      description: "Action with nil message error"

    def run(_params, _context), do: {:error, %{message: nil}}
  end

  defmodule StructMessageErrorAction do
    use Action,
      name: "struct_message_error",
      description: "Action with struct message error"

    def run(_params, _context) do
      {:error, %{message: %ArgumentError{message: "struct message"}}}
    end
  end

  defmodule BasicStruct do
    defstruct [:value]
  end

  defmodule StructNoMessageAction do
    use Action,
      name: "struct_no_message",
      description: "Action with struct without message field"

    def run(_params, _context) do
      {:error, %{message: %JidoTest.CoverageTestActions.BasicStruct{value: "test"}}}
    end
  end

  defmodule BadArityAction do
    use Action,
      name: "bad_arity",
      description: "Action that causes bad arity error"

    def run(%{cause_error: true}, _context) do
      fun = fn -> :ok end
      fun.(:extra, :args)
    end

    def run(params, _context), do: {:ok, params}
  end

  defmodule ThrowAction do
    use Action,
      name: "throw_action",
      description: "Action that throws"

    def run(%{cause_throw: true}, _context), do: throw("something was thrown")
    def run(params, _context), do: {:ok, params}
  end

  defmodule ExitAction do
    use Action,
      name: "exit_action",
      description: "Action that exits"

    def run(%{cause_exit: true}, _context), do: exit("normal exit")
    def run(params, _context), do: {:ok, params}
  end

  # ── exec_final_coverage_test.exs ──

  defmodule ErrorMessageTestAction do
    use Action,
      name: "error_message_test",
      description: "Test error message extraction"

    def run(%{error_type: :nil_message}, _context), do: {:error, %{message: nil}}
    def run(%{error_type: :string_message}, _context), do: {:error, %{message: "string error"}}

    def run(%{error_type: :struct_message}, _context),
      do: {:error, %{message: %ArgumentError{message: "struct error"}}}

    def run(%{error_type: :nested_message}, _context),
      do: {:error, %{message: %{message: "nested error"}}}

    def run(%{error_type: :no_message}, _context), do: {:error, %{other: "field"}}
    def run(params, _context), do: {:ok, params}
  end

  defmodule RetryPatternAction do
    use Action,
      name: "retry_pattern",
      description: "Action with specific retry patterns"

    def run(%{pattern: :immediate_success}, _context), do: {:ok, %{result: "immediate"}}

    def run(%{pattern: :fail_once, attempt: _attempt}, context) do
      current_attempt = Map.get(context, :current_attempt, 0) + 1

      if current_attempt == 1 do
        {:error, Error.execution_error("first attempt fails")}
      else
        {:ok, %{result: "success on attempt #{current_attempt}"}}
      end
    end

    def run(params, _context), do: {:ok, params}
  end

  defmodule TaskSpawningAction do
    use Action,
      name: "task_spawning",
      description: "Action that spawns tasks"

    def run(_params, _context) do
      {:ok, _pid} = Task.start(fn -> Process.sleep(10) end)
      {:ok, %{spawned: true}}
    end
  end

  defmodule ResultNormalizationAction do
    use Action,
      name: "result_normalization",
      description: "Action with various result types"

    def run(%{result_type: :standard_ok}, _context), do: {:ok, %{standard: true}}

    def run(%{result_type: :three_tuple_ok}, _context),
      do: {:ok, %{three_tuple: true}, %{directive: "test"}}

    def run(%{result_type: :three_tuple_error}, _context),
      do: {:error, Error.execution_error("three tuple error"), %{directive: "error"}}

    def run(%{result_type: :raw_value}, _context), do: %{raw: true}
    def run(params, _context), do: {:ok, params}
  end

  defmodule NoValidateOutputAction do
    use Action,
      name: "no_validate_output",
      description: "Action without validate_output"

    def run(params, _context), do: {:ok, params}
  end

  defmodule CompensationOptsAction do
    use Action,
      name: "compensation_opts",
      description: "Action testing compensation with opts",
      compensation: [enabled: true]

    def run(_params, _context), do: {:error, Error.execution_error("test error")}

    def on_error(_params, _error, _context, _opts) do
      Process.sleep(80)
      {:ok, %{compensated: true}}
    end
  end

  # ── exec_misc_coverage_test.exs ──

  defmodule StructMessageAction do
    use Action, name: "struct_message", description: "Test struct message"

    def run(_params, _context) do
      struct_with_message = %ArgumentError{message: "argument error"}
      {:error, %{message: struct_with_message}}
    end
  end

  defmodule SpecificTimeoutCompAction do
    use Action,
      name: "specific_timeout_comp",
      description: "Compensation with specific timeout",
      compensation: [enabled: true, timeout: 30]

    def run(_params, _context), do: {:error, Error.execution_error("compensation test")}

    def on_error(_params, _error, _context, _opts) do
      Process.sleep(60)
      {:ok, %{compensated: true}}
    end
  end

  defmodule CleanupTestAction do
    use Action, name: "cleanup_test", description: "Test cleanup"

    def run(_params, _context) do
      Process.sleep(100)
      {:ok, %{}}
    end
  end

  defmodule CatchTestAction do
    use Action, name: "catch_test", description: "Test catch clauses"

    def run(%{error_type: :throw}, _context), do: throw("test throw")
    def run(%{error_type: :exit}, _context), do: exit("test exit")
    def run(params, _context), do: {:ok, params}
  end

  defmodule SmallBackoffAction do
    use Action, name: "small_backoff", description: "Test small backoff"

    def run(%{succeed: true}, _context), do: {:ok, %{succeeded: true}}
    def run(params, _context), do: {:ok, params}
  end

  # ── exec_output_validation_test.exs ──

  defmodule TupleOutputAction do
    use Action,
      name: "tuple_output_action",
      output_schema: [
        status: [type: :string, required: true]
      ]

    def run(_params, _context), do: {:ok, %{status: "success", extra: "data"}, :continue}
  end

  defmodule InvalidTupleOutputAction do
    use Action,
      name: "invalid_tuple_output_action",
      output_schema: [
        required_field: [type: :string, required: true]
      ]

    def run(_params, _context), do: {:ok, %{wrong_field: "value"}, :continue}
  end

  defmodule TypeErrorOutputAction do
    use Action,
      name: "type_error_output_action",
      output_schema: [
        count: [type: :integer, required: true]
      ]

    def run(_params, _context), do: {:ok, %{count: "not an integer"}}
  end

  defmodule CallbackErrorOutputAction do
    use Action,
      name: "callback_error_output_action",
      output_schema: [
        value: [type: :string, required: true]
      ]

    def run(_params, _context), do: {:ok, %{value: "test"}}

    def on_before_validate_output(_output) do
      {:error, Error.validation_error("Callback failed")}
    end
  end

  # ── exec_timeout_task_supervisor_test.exs ──

  defmodule FastAction do
    use Action, name: "fast_action"
    def run(_params, _context), do: {:ok, %{completed: true}}
  end

  defmodule SlowAction do
    use Action, name: "slow_action"

    def run(_params, _context) do
      Process.sleep(100)
      {:ok, %{completed: true}}
    end
  end

  defmodule TimeoutMessageAction do
    use Action, name: "timeout_message_action"

    def run(_params, _context) do
      Process.sleep(100)
      {:ok, %{}}
    end
  end

  defmodule IOActionCoverage do
    use Action, name: "io_action"

    def run(_params, _context) do
      IO.puts("test output")
      {:ok, %{io_worked: true}}
    end
  end

  defmodule ChildSpawningAction do
    use Action, name: "child_spawning_action"

    def run(_params, context) do
      child_pid =
        spawn_link(fn ->
          send(context.test_pid, {:child_started, self()})
          Process.sleep(10_000)
        end)

      send(context.test_pid, {:parent_has_child, child_pid})
      Process.sleep(10_000)
      {:ok, %{done: true}}
    end
  end

  defmodule ExitingAction do
    use Action, name: "exiting_action"

    def run(_params, _context) do
      Process.exit(self(), :shutdown)
      {:ok, %{}}
    end
  end

  defmodule KillableActionSupervisor do
    use Action, name: "killable_action"

    def run(_params, _context) do
      Process.exit(self(), :kill)
      {:ok, %{}}
    end
  end

  defmodule ConcurrentAction do
    use Action, name: "concurrent_action"

    def run(params, _context) do
      Process.sleep(params[:delay])
      {:ok, %{id: params[:id]}}
    end
  end

  defmodule LeakTestAction do
    use Action, name: "leak_test_action"

    def run(_params, _context) do
      Process.sleep(100)
      {:ok, %{}}
    end
  end

  # ── exec_config_test.exs ──

  defmodule ConfigTestAction do
    use Action, name: "config_test", description: "Config test action"

    def run(%{should_fail: true}, _context),
      do: {:error, Error.execution_error("config test error")}

    def run(params, _context), do: {:ok, params}
  end

  defmodule AllConfigPathsAction do
    use Action, name: "all_config_paths", description: "Triggers all config paths"

    def run(%{attempt: attempt}, _context) when attempt < 2,
      do: {:error, Error.execution_error("retry error")}

    def run(params, _context), do: {:ok, params}
  end
end
