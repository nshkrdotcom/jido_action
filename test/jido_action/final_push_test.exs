defmodule JidoTest.FinalPushTest do
  @moduledoc """
  Final targeted tests to push coverage above 90%.
  Targets:
  - Plan.ex cycle detection (lines 418, 422, 439, 446, 451)
  - Plan.ex validate_dependencies! with non-atom deps (lines 339-340)
  - Plan.ex add_depends_on_to_step_def with keyword list opts (line 505)
  """
  use ExUnit.Case, async: true

  alias Jido.Plan
  alias JidoTest.TestActions.Add

  @moduletag :capture_log

  # ---- Plan.ex: Cycle detection (covers ~5 uncovered DFS lines) ----
  # Creates a plan with both acyclic vertices (C→D) and a cycle (A↔B).
  # The DFS visits C and D first (no cycle), then finds the cycle on A↔B.
  # This exercises dfs_neighbors base case, dfs_visit ok case, and find_cycle_dfs
  # continuation after visiting an acyclic subgraph.
  describe "Plan.normalize/1 with circular dependencies" do
    test "returns error for cyclic plan with isolated acyclic vertices" do
      plan =
        Plan.new()
        |> Plan.add(:c, Add)
        |> Plan.add(:d, Add, depends_on: :c)
        |> Plan.add(:a, Add, depends_on: :b)
        |> Plan.add(:b, Add, depends_on: :a)

      assert {:error, %Jido.Action.Error.InvalidInputError{} = error} =
               Plan.normalize(plan)

      assert error.message =~ "circular dependencies"
    end
  end

  # ---- Plan.ex: Non-atom dependencies (lines 339-340) ----
  describe "Plan.add/4 with non-atom dependencies" do
    test "raises when depends_on contains non-atom" do
      plan = Plan.new() |> Plan.add(:step1, Add)

      assert_raise Jido.Action.Error.InvalidInputError, ~r/dependencies must be atoms/, fn ->
        Plan.add(plan, :step2, Add, depends_on: ["not_an_atom"])
      end
    end
  end

  # ---- Plan.ex: to_keyword with opts-based step def (line 505) ----
  describe "Plan.to_keyword/1 with opts-based step definitions" do
    test "converts plan with action+opts and deps to keyword list" do
      # Create a step with keyword list opts (not map params) + dependencies.
      # This exercises the {action, opts} when is_list(opts) branch of
      # add_depends_on_to_step_def (line 505).
      plan =
        Plan.new()
        |> Plan.add(:step1, Add)
        |> Plan.add(:step2, {Add, [timeout: 5000]}, depends_on: :step1)

      kw = Plan.to_keyword(plan)
      assert length(kw) == 2

      {_name, step2_def} = Enum.find(kw, fn {name, _} -> name == :step2 end)
      assert is_tuple(step2_def)
    end
  end
end
