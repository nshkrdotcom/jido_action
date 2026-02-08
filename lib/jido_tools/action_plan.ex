defmodule Jido.Tools.ActionPlan do
  @moduledoc """
  A behavior and macro for creating actions that execute Jido Plans.

  Provides a standardized way to create actions that build and execute plans
  with configurable plan building and result transformation.

  ## Usage

  ```elixir
  defmodule MyWorkflowAction do
    use Jido.Tools.ActionPlan,
      name: "my_workflow",
      description: "Executes a multi-step workflow"

    @impl Jido.Tools.ActionPlan
    def build(params, context) do
      Plan.new(context: context)
      |> Plan.add(:fetch, MyApp.FetchAction, params)
      |> Plan.add(:validate, MyApp.ValidateAction, depends_on: :fetch)
      |> Plan.add(:save, MyApp.SaveAction, depends_on: :validate)
    end

    @impl Jido.Tools.ActionPlan
    def transform_result(result) do
      # Optional: Transform the execution result
      {:ok, %{workflow_result: result}}
    end
  end
  ```

  ## Callbacks

  - `build/2` (required) - Build the Plan struct from params and context
  - `transform_result/1` (optional) - Transform the execution result
  """

  alias Jido.Plan

  @doc """
  Required callback for building a Plan struct.

  Takes the action parameters and context and returns a Plan struct
  that will be executed.
  """
  @callback build(params :: map(), context :: map()) :: Plan.t()

  @doc """
  Optional callback for transforming the execution result.

  Takes the plan execution result and returns a transformed result.
  """
  @callback transform_result(map()) :: {:ok, map()} | {:error, any()}

  # Make transform_result optional
  @optional_callbacks [transform_result: 1]

  @doc """
  Macro for setting up a module as an ActionPlan with plan execution capabilities.
  """
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour Jido.Tools.ActionPlan
      use Jido.Action, unquote(opts)

      alias Jido.Tools.ActionPlan.Runner

      @impl Jido.Action
      def run(params, context) do
        plan = build(params, context)

        case Runner.execute_plan(plan, params, context) do
          {:ok, result} ->
            transform_result(result)
            |> Runner.normalize_transform_result()

          {:error, reason} ->
            {:error, Runner.ensure_error(reason, "Plan execution failed")}
        end
      end

      @impl Jido.Tools.ActionPlan
      def transform_result(result) do
        {:ok, result}
      end

      defoverridable transform_result: 1
    end
  end
end
