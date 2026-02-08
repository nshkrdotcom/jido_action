defmodule JidoTest.Tools.Workflow.ExecutionCoverageTest do
  @moduledoc """
  Additional coverage tests for Jido.Tools.Workflow.Execution.
  """
  use JidoTest.ActionCase, async: true

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

  defmodule TestWorkflow do
    use Jido.Tools.Workflow,
      name: "test_execution_workflow",
      description: "Test workflow for execution coverage",
      schema: [],
      workflow: [
        {:step, [name: "ok_step"], [{OkAction, []}]}
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
end
