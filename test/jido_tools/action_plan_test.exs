defmodule Jido.Tools.ActionPlanTest do
  use ExUnit.Case, async: true

  alias Jido.Plan
  alias Jido.Tools.ActionPlan

  # Test actions for workflow execution
  defmodule TestAction do
    use Jido.Action,
      name: "test_action",
      description: "A test action"

    @impl Jido.Action
    def run(params, _context) do
      result = Map.get(params, :result, "test_result")
      {:ok, %{result: result}}
    end
  end

  defmodule AddAction do
    use Jido.Action,
      name: "add_action",
      description: "Adds two numbers"

    @impl Jido.Action
    def run(params, _context) do
      a = Map.get(params, :a, 0)
      b = Map.get(params, :b, 0)
      {:ok, %{sum: a + b}}
    end
  end

  defmodule MultiplyAction do
    use Jido.Action,
      name: "multiply_action",
      description: "Multiplies a number by 2"

    @impl Jido.Action
    def run(params, _context) do
      # Look for sum in the params (passed from previous step)
      value = Map.get(params, :sum, 0)
      {:ok, %{product: value * 2}}
    end
  end

  defmodule FailingAction do
    use Jido.Action,
      name: "failing_action",
      description: "An action that always fails"

    @impl Jido.Action
    def run(_params, _context) do
      {:error, "This action always fails"}
    end
  end

  # Test ActionPlan implementations
  defmodule SimpleActionPlan do
    use ActionPlan,
      name: "simple_workflow",
      description: "A simple workflow with one step"

    @impl ActionPlan
    def build(_params, context) do
      Plan.new(context: context)
      |> Plan.add(:test_step, TestAction)
    end
  end

  defmodule SequentialActionPlan do
    use ActionPlan,
      name: "sequential_workflow",
      description: "A workflow with sequential steps"

    @impl ActionPlan
    def build(params, context) do
      Plan.new(context: context)
      |> Plan.add(:add, {AddAction, %{a: params[:a] || 1, b: params[:b] || 2}})
      |> Plan.add(:multiply, MultiplyAction, depends_on: :add)
    end
  end

  defmodule ParallelActionPlan do
    use ActionPlan,
      name: "parallel_workflow",
      description: "A workflow with parallel steps"

    @impl ActionPlan
    def build(_params, context) do
      Plan.new(context: context)
      |> Plan.add(:step1, {TestAction, %{result: "result1"}})
      |> Plan.add(:step2, {TestAction, %{result: "result2"}})
      |> Plan.add(:merge, TestAction, depends_on: [:step1, :step2])
    end
  end

  defmodule TransformingActionPlan do
    use ActionPlan,
      name: "transforming_workflow",
      description: "A workflow that transforms results"

    @impl ActionPlan
    def build(_params, context) do
      Plan.new(context: context)
      |> Plan.add(:test_step, TestAction)
    end

    @impl ActionPlan
    def transform_result(result) do
      {:ok, %{transformed: true, original: result}}
    end
  end

  defmodule FailingActionPlan do
    use ActionPlan,
      name: "failing_workflow",
      description: "A workflow with a failing step"

    @impl ActionPlan
    def build(_params, context) do
      Plan.new(context: context)
      |> Plan.add(:failing_step, FailingAction)
    end
  end

  defmodule InvalidActionPlan do
    use ActionPlan,
      name: "invalid_workflow",
      description: "A workflow that causes execution issues"

    @impl ActionPlan
    def build(_params, context) do
      # Create a plan with a circular dependency to cause execution failure
      Plan.new(context: context)
      |> Plan.add(:step1, TestAction, depends_on: :step2)
      |> Plan.add(:step2, TestAction, depends_on: :step1)
    end
  end

  describe "ActionPlan behavior" do
    test "simple workflow executes successfully" do
      params = %{}
      context = %{}

      assert {:ok, result} = SimpleActionPlan.run(params, context)
      assert %{test_step: %{result: "test_result"}} = result
    end

    test "sequential workflow executes in order" do
      params = %{a: 5, b: 3}
      context = %{}

      assert {:ok, result} = SequentialActionPlan.run(params, context)
      # The multiply step should receive the sum from the add step
      assert %{add: %{sum: 8}, multiply: %{product: 16}} = result
    end

    test "parallel workflow executes parallel steps" do
      params = %{}
      context = %{}

      assert {:ok, result} = ParallelActionPlan.run(params, context)
      assert %{step1: %{result: "result1"}, step2: %{result: "result2"}} = result
      assert Map.has_key?(result, :merge)
    end

    test "workflow with transform_result callback" do
      params = %{}
      context = %{}

      assert {:ok, result} = TransformingActionPlan.run(params, context)
      assert %{transformed: true, original: %{test_step: %{result: "test_result"}}} = result
    end

    test "workflow handles step failures" do
      params = %{}
      context = %{}

      assert {:error, error} = FailingActionPlan.run(params, context)
      assert %{type: :step_execution_failed, step_name: :failing_step} = error
      # The error is now wrapped in a Jido.Action.Error struct by Jido.Exec
      assert is_exception(error.reason)
      assert Exception.message(error.reason) =~ "This action always fails"
    end

    test "workflow handles plan execution failures" do
      params = %{}
      context = %{}

      assert {:error, error} = InvalidActionPlan.run(params, context)
      # Should fail due to circular dependency
      assert error.message =~ "circular dependencies"
    end
  end

  describe "ActionPlan module attributes" do
    test "has correct name and description" do
      assert SimpleActionPlan.name() == "simple_workflow"
      assert SimpleActionPlan.description() == "A simple workflow with one step"
    end

    test "inherits Action behavior" do
      assert function_exported?(SimpleActionPlan, :run, 2)
      assert function_exported?(SimpleActionPlan, :name, 0)
      assert function_exported?(SimpleActionPlan, :description, 0)
    end
  end

  describe "error handling" do
    test "handles missing steps gracefully" do
      # Test that we can handle a plan with missing dependencies
      # The Plan module should create a graph with missing vertices
      plan =
        Plan.new()
        |> Plan.add(:existing_step, TestAction)
        |> Plan.add(:bad_step, TestAction, depends_on: [:non_existent])

      # The execution_phases will succeed but the missing vertex will be included
      # This is actually valid behavior - the graph includes the missing dependency
      assert {:ok, phases} = Plan.execution_phases(plan)
      # The phases will include the non_existent step even though it's not defined
      assert length(phases) >= 2
    end
  end
end
