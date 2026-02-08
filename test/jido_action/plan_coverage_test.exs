defmodule JidoTest.PlanCoverageTest do
  @moduledoc """
  Coverage tests for Jido.Plan uncovered paths:
  - build!/2 success and error
  - normalize!/1
  - execution_phases/1
  - to_keyword/1 with deps
  - depends_on/3 with missing step
  - add_depends_on_to_step_def variants
  - instruction_to_step_def variants
  """
  use ExUnit.Case, async: true

  alias Jido.Plan
  alias JidoTest.TestActions.Add

  @moduletag :capture_log

  describe "build!/2" do
    test "returns plan for valid keyword list" do
      plan = Plan.build!(step1: Add)
      assert %Plan{} = plan
      assert Map.has_key?(plan.steps, :step1)
    end

    test "raises on invalid plan definition" do
      assert_raise FunctionClauseError, fn ->
        Plan.build!("not a keyword list")
      end
    end

    test "raises on non-keyword list" do
      assert {:error, %Jido.Action.Error.InvalidInputError{}} =
               Plan.build([{"not", "keyword"}])
    end
  end

  describe "normalize!/1" do
    test "returns graph and instructions for valid plan" do
      plan =
        Plan.new()
        |> Plan.add(:step1, Add)

      {graph, instructions} = Plan.normalize!(plan)
      assert is_struct(graph, Graph)
      assert length(instructions) == 1
    end
  end

  describe "execution_phases/1" do
    test "returns phases for sequential plan" do
      plan =
        Plan.new()
        |> Plan.add(:step1, Add)
        |> Plan.add(:step2, Add, depends_on: :step1)

      assert {:ok, phases} = Plan.execution_phases(plan)
      assert length(phases) == 2
    end

    test "returns parallel phases for independent steps" do
      plan =
        Plan.new()
        |> Plan.add(:step1, Add)
        |> Plan.add(:step2, Add)

      assert {:ok, phases} = Plan.execution_phases(plan)
      assert length(phases) == 1
      [first_phase] = phases
      assert length(first_phase) == 2
    end
  end

  describe "depends_on/3" do
    test "raises for non-existent step" do
      plan =
        Plan.new()
        |> Plan.add(:step1, Add)

      assert_raise Jido.Action.Error.InvalidInputError, fn ->
        Plan.depends_on(plan, :nonexistent, :step1)
      end
    end

    test "adds dependency to existing step" do
      plan =
        Plan.new()
        |> Plan.add(:step1, Add)
        |> Plan.add(:step2, Add)
        |> Plan.depends_on(:step2, :step1)

      assert :step1 in plan.steps[:step2].depends_on
    end
  end

  describe "to_keyword/1" do
    test "converts plan with deps to keyword list" do
      plan =
        Plan.new()
        |> Plan.add(:step1, Add)
        |> Plan.add(:step2, Add, depends_on: :step1)

      kw = Plan.to_keyword(plan)
      assert is_list(kw)
      assert length(kw) == 2

      {_name, step2_def} = Enum.find(kw, fn {name, _} -> name == :step2 end)
      # step2 has a dependency, so it should be a tuple with depends_on
      assert is_tuple(step2_def)
    end

    test "converts plan with params to keyword list" do
      plan =
        Plan.new()
        |> Plan.add(:step1, {Add, %{value: 1, amount: 2}})

      kw = Plan.to_keyword(plan)
      assert length(kw) == 1
      {_name, step_def} = hd(kw)
      assert is_tuple(step_def)
    end

    test "converts plan with params and deps to keyword list" do
      plan =
        Plan.new()
        |> Plan.add(:step1, Add)
        |> Plan.add(:step2, {Add, %{value: 1, amount: 2}}, depends_on: :step1)

      kw = Plan.to_keyword(plan)
      {_name, step2_def} = Enum.find(kw, fn {name, _} -> name == :step2 end)
      assert tuple_size(step2_def) == 3
    end
  end

  describe "build/2 with step definitions containing depends_on" do
    test "builds plan from keyword list with depends_on in tuples" do
      plan_def = [
        fetch: Add,
        validate: {Add, depends_on: :fetch}
      ]

      assert {:ok, %Plan{} = plan} = Plan.build(plan_def)
      assert :fetch in plan.steps[:validate].depends_on
    end

    test "builds plan from keyword list with params and depends_on" do
      plan_def = [
        fetch: Add,
        validate: {Add, %{value: 1, amount: 2}, depends_on: :fetch}
      ]

      assert {:ok, %Plan{} = plan} = Plan.build(plan_def)
      assert :fetch in plan.steps[:validate].depends_on
    end
  end
end
