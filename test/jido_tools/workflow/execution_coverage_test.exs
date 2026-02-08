defmodule JidoTest.Tools.Workflow.ExecutionCoverageTest do
  @moduledoc """
  Additional coverage tests for Jido.Tools.Workflow.Execution.
  """
  use JidoTest.ActionCase, async: true

  alias Jido.Exec
  alias Jido.Tools.Workflow.Execution

  @moduletag :capture_log

  defmodule NonMapResultAction do
    use Jido.Action,
      name: "non_map_result_action",
      description: "Returns a non-map result",
      schema: []

    @dialyzer {:nowarn_function, run: 2}
    @impl true
    def run(_params, _context) do
      {:ok, "not a map"}
    end
  end

  defmodule RaisingAction do
    use Jido.Action,
      name: "raising_action",
      description: "Raises during execution",
      schema: []

    @impl true
    def run(_params, _context) do
      raise "intentional explosion"
    end
  end

  defmodule StringErrorAction do
    use Jido.Action,
      name: "string_error_action",
      description: "Returns a string error",
      schema: []

    @impl true
    def run(_params, _context) do
      {:error, "plain string error"}
    end
  end

  defmodule OkAction do
    use Jido.Action,
      name: "ok_action",
      description: "Returns ok",
      schema: []

    @impl true
    def run(_params, _context) do
      {:ok, %{done: true}}
    end
  end

  defmodule SlowAction do
    use Jido.Action,
      name: "slow_action",
      description: "Sleeps before returning",
      schema: []

    @impl true
    def run(_params, _context) do
      Process.sleep(100)
      {:ok, %{done: true}}
    end
  end

  defmodule OkWithDirectiveAction do
    use Jido.Action,
      name: "ok_with_directive_action",
      description: "Returns ok with directive",
      schema: []

    @impl true
    def run(_params, _context) do
      {:ok, %{done: true}, :workflow_directive}
    end
  end

  defmodule ErrorWithDirectiveAction do
    use Jido.Action,
      name: "error_with_directive_action",
      description: "Returns error with directive",
      schema: []

    alias Jido.Action.Error

    @impl true
    def run(_params, _context) do
      {:error, Error.execution_error("directive failure"), :workflow_error_directive}
    end
  end

  defmodule RetryProbeAction do
    use Jido.Action,
      name: "retry_probe_action",
      description: "Tracks execution attempts for workflow retries",
      schema: [
        counter: [type: :any, required: true],
        fail_attempts: [type: :integer, required: true]
      ]

    alias Jido.Action.Error

    @impl true
    def run(%{counter: counter, fail_attempts: fail_attempts}, _context) do
      attempt = Agent.get_and_update(counter, fn current -> {current + 1, current + 1} end)

      if attempt <= fail_attempts do
        {:error, Error.execution_error("retry probe failure")}
      else
        {:ok, %{attempt: attempt}}
      end
    end
  end

  defmodule SleepAndNotifyAction do
    use Jido.Action,
      name: "sleep_and_notify_action",
      description: "Sleeps and optionally notifies a process",
      schema: [
        ms: [type: :non_neg_integer, required: true],
        notify: [type: :any]
      ]

    @impl true
    def run(%{ms: ms} = params, _context) do
      Process.sleep(ms)

      case Map.get(params, :notify) do
        pid when is_pid(pid) -> send(pid, :parallel_task_completed)
        _ -> :ok
      end

      {:ok, %{slept: ms}}
    end
  end

  defmodule TestWorkflow do
    use Jido.Tools.Workflow,
      name: "test_execution_workflow",
      description: "Test workflow for execution coverage",
      schema: [],
      workflow: [
        {:step, [name: "ok_step"], [{OkAction, []}]}
      ]
  end

  defmodule ParallelTimeoutWorkflow do
    use Jido.Tools.Workflow,
      name: "parallel_timeout_workflow",
      description: "Workflow used to verify parallel task cancellation on timeout",
      schema: [
        notify: [type: :any]
      ],
      workflow: [
        {:parallel, [name: "par_cancel", max_concurrency: 2],
         [
           {:step, [name: "sleep_1"], [{SleepAndNotifyAction, %{ms: 300}}]},
           {:step, [name: "sleep_2"], [{SleepAndNotifyAction, %{ms: 300}}]}
         ]}
      ]
  end

  describe "execute_step/4 with unknown step type" do
    test "returns error for unknown step type" do
      assert {:error, %Jido.Action.Error.InvalidInputError{} = error} =
               Execution.execute_step({:unknown_type, [], []}, %{}, %{}, TestWorkflow)

      assert error.details.type == :invalid_step
    end
  end

  describe "execute_step/4 with converge step" do
    test "executes converge step as instruction" do
      step = {:converge, [name: "converge"], [{OkAction, []}]}

      assert {:ok, %{done: true}} =
               Execution.execute_step(step, %{}, %{}, TestWorkflow)
    end
  end

  describe "execute_workflow/4 with non-map step results" do
    test "returns error when step returns non-map result" do
      steps = [{:step, [name: "bad"], [{NonMapResultAction, []}]}]

      assert {:error, _} =
               Execution.execute_workflow(steps, %{}, %{}, TestWorkflow)
    end
  end

  describe "execute_workflow/4 with string error" do
    test "handles string error from action" do
      steps = [{:step, [name: "string_err"], [{StringErrorAction, []}]}]

      assert {:error, %Jido.Action.Error.ExecutionFailureError{}} =
               Execution.execute_workflow(steps, %{}, %{}, TestWorkflow)
    end
  end

  describe "directive propagation" do
    test "execute_step/4 returns directive from action result" do
      step = {:step, [name: "ok_directive"], [{OkWithDirectiveAction, []}]}

      assert {:ok, %{done: true}, :workflow_directive} =
               Execution.execute_step(step, %{}, %{}, TestWorkflow)
    end

    test "execute_workflow/4 returns latest successful directive" do
      steps = [
        {:step, [name: "ok"], [{OkAction, []}]},
        {:step, [name: "ok_directive"], [{OkWithDirectiveAction, []}]}
      ]

      assert {:ok, %{done: true}, :workflow_directive} =
               Execution.execute_workflow(steps, %{}, %{}, TestWorkflow)
    end

    test "execute_workflow/4 returns directive from failing step" do
      steps = [
        {:step, [name: "failing_directive"], [{ErrorWithDirectiveAction, []}]}
      ]

      assert {:error, %Jido.Action.Error.ExecutionFailureError{} = error,
              :workflow_error_directive} =
               Execution.execute_workflow(steps, %{}, %{}, TestWorkflow)

      assert error.message =~ "directive failure"
    end
  end

  describe "execute_step/4 with parallel steps" do
    test "executes parallel steps and collects results" do
      instructions = [
        {:step, [name: "p1"], [{OkAction, []}]},
        {:step, [name: "p2"], [{OkAction, []}]}
      ]

      step = {:parallel, [name: "par", max_concurrency: 2], instructions}

      assert {:ok, %{parallel_results: results}} =
               Execution.execute_step(step, %{}, %{}, TestWorkflow)

      assert length(results) == 2
    end

    test "supports instance context for parallel execution" do
      instructions = [
        {:step, [name: "p1"], [{OkAction, []}]},
        {:step, [name: "p2"], [{OkAction, []}]}
      ]

      step = {:parallel, [name: "par_jido", max_concurrency: 1], instructions}
      context = %{__jido__: Jido.Action}

      assert {:ok, %{parallel_results: results}} =
               Execution.execute_step(step, %{}, context, TestWorkflow)

      assert length(results) == 2
    end

    test "applies finite parallel timeout from metadata" do
      instructions = [
        {:step, [name: "slow"], [{SlowAction, []}]}
      ]

      step = {:parallel, [name: "par_timeout", max_concurrency: 1, timeout: 10], instructions}

      assert {:ok, %{parallel_results: [result]}} =
               Execution.execute_step(step, %{}, %{}, TestWorkflow)

      assert %{
               error: %Jido.Action.Error.ExecutionFailureError{message: message}
             } = result

      assert message =~ "Parallel task exited"
    end

    test "parallel tasks do not outlive workflow timeout" do
      run_result =
        Exec.run(ParallelTimeoutWorkflow, %{notify: self()}, %{},
          timeout: 50,
          max_retries: 0
        )

      assert timeout_or_parallel_timeout_result?(run_result),
             "expected workflow timeout outcome, got: #{inspect(run_result)}"

      refute_receive :parallel_task_completed, 700
    end
  end

  describe "execute_step/4 with branch" do
    test "executes true branch for boolean true condition" do
      true_branch = {:step, [name: "yes"], [{OkAction, []}]}
      false_branch = {:step, [name: "no"], [{StringErrorAction, []}]}
      step = {:branch, [name: "br"], [true, true_branch, false_branch]}

      assert {:ok, %{done: true}} =
               Execution.execute_step(step, %{}, %{}, TestWorkflow)
    end

    test "executes false branch for boolean false condition" do
      true_branch = {:step, [name: "yes"], [{StringErrorAction, []}]}
      false_branch = {:step, [name: "no"], [{OkAction, []}]}
      step = {:branch, [name: "br"], [false, true_branch, false_branch]}

      assert {:ok, %{done: true}} =
               Execution.execute_step(step, %{}, %{}, TestWorkflow)
    end

    test "returns error for non-boolean condition" do
      true_branch = {:step, [name: "yes"], [{OkAction, []}]}
      false_branch = {:step, [name: "no"], [{OkAction, []}]}
      step = {:branch, [name: "br"], ["not_bool", true_branch, false_branch]}

      assert {:error, %Jido.Action.Error.InvalidInputError{} = error} =
               Execution.execute_step(step, %{}, %{}, TestWorkflow)

      assert error.details.type == :invalid_condition
    end
  end

  describe "internal instruction retry defaults" do
    test "defaults instruction timeout to configured execution timeout" do
      original_timeout = Application.get_env(:jido_action, :default_timeout)
      Application.put_env(:jido_action, :default_timeout, 10)

      on_exit(fn ->
        if is_nil(original_timeout) do
          Application.delete_env(:jido_action, :default_timeout)
        else
          Application.put_env(:jido_action, :default_timeout, original_timeout)
        end
      end)

      step = {:step, [name: "slow_with_default_timeout"], [{SlowAction, []}]}

      assert {:error, %Jido.Action.Error.TimeoutError{timeout: 10}} =
               Execution.execute_step(step, %{}, %{}, TestWorkflow)
    end

    test "defaults max_retries to 0 when instruction does not provide it" do
      original_max_retries = Application.get_env(:jido_action, :default_max_retries)
      Application.put_env(:jido_action, :default_max_retries, 2)

      {:ok, counter} = Agent.start_link(fn -> 0 end)

      on_exit(fn ->
        if is_nil(original_max_retries) do
          Application.delete_env(:jido_action, :default_max_retries)
        else
          Application.put_env(:jido_action, :default_max_retries, original_max_retries)
        end

        if Process.alive?(counter), do: Agent.stop(counter)
      end)

      step =
        {:step, [name: "retry_probe"],
         [{RetryProbeAction, %{counter: counter, fail_attempts: 1}}]}

      assert {:error, %Jido.Action.Error.ExecutionFailureError{}} =
               Execution.execute_step(step, %{}, %{}, TestWorkflow)

      assert Agent.get(counter, & &1) == 1
    end

    test "preserves explicit max_retries from instruction opts" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      on_exit(fn ->
        if Process.alive?(counter), do: Agent.stop(counter)
      end)

      step =
        {:step, [name: "retry_probe_with_opts"],
         [
           {RetryProbeAction, %{counter: counter, fail_attempts: 1}, %{},
            [max_retries: 2, backoff: 1]}
         ]}

      assert {:ok, %{attempt: 2}} = Execution.execute_step(step, %{}, %{}, TestWorkflow)
      assert Agent.get(counter, & &1) == 2
    end
  end

  defp timeout_or_parallel_timeout_result?({:error, %Jido.Action.Error.TimeoutError{}}), do: true

  defp timeout_or_parallel_timeout_result?({:ok, %{parallel_results: results}})
       when is_list(results) and results != [] do
    Enum.all?(results, &parallel_timeout_result?/1)
  end

  defp timeout_or_parallel_timeout_result?(_), do: false

  defp parallel_timeout_result?(%{error: %Jido.Action.Error.TimeoutError{}}), do: true

  defp parallel_timeout_result?(%{
         error: %Jido.Action.Error.ExecutionFailureError{details: details}
       })
       when is_map(details) do
    Map.get(details, :reason) == :timeout
  end

  defp parallel_timeout_result?(_), do: false
end
