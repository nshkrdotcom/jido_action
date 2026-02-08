defmodule Jido.Tools.ActionPlan.Runner do
  @moduledoc false

  alias Jido.Action.Error
  alias Jido.Exec
  alias Jido.Plan

  @doc """
  Executes a plan by deriving execution phases and running them sequentially.
  """
  def execute_plan(plan, params, context) do
    case Plan.execution_phases(plan) do
      {:ok, phases} ->
        execute_phases(phases, plan, params, context, %{})

      {:error, reason} ->
        {:error, ensure_error(reason, "Failed to derive plan execution phases")}
    end
  end

  @doc """
  Normalizes the return value of `transform_result/1` into `{:ok, _}` or `{:error, _}`.
  """
  def normalize_transform_result(result) do
    cond do
      match?({:ok, _}, result) ->
        {:ok, elem(result, 1)}

      match?({:error, _}, result) ->
        {:error, ensure_error(elem(result, 1), "Result transformation failed")}

      true ->
        {:error,
         Error.execution_error("Invalid transform_result return value", %{result: result})}
    end
  end

  @doc """
  Wraps an arbitrary reason in an `Error` struct when it isn't one already.
  """
  def ensure_error(%_{} = error, _message) when is_exception(error), do: error

  def ensure_error(reason, _message) when is_binary(reason) do
    Error.execution_error(reason)
  end

  def ensure_error(reason, message) do
    Error.execution_error(message, %{reason: reason})
  end

  # -- private helpers -------------------------------------------------------

  defp execute_phases([], _plan, _params, _context, results) do
    {:ok, results}
  end

  defp execute_phases([phase | remaining_phases], plan, params, context, results) do
    case execute_phase(phase, plan, params, context, results) do
      {:ok, phase_results} ->
        updated_results = Map.merge(results, phase_results)

        flattened_results =
          Enum.reduce(phase_results, %{}, fn {_step_name, step_result}, acc ->
            Map.merge(acc, step_result)
          end)

        updated_params = Map.merge(params, flattened_results)
        execute_phases(remaining_phases, plan, updated_params, context, updated_results)

      {:error, reason} ->
        {:error, ensure_error(reason, "Action plan phase failed")}
    end
  end

  defp execute_phase(step_names, plan, params, context, _results) when is_list(step_names) do
    step_results =
      step_names
      |> Enum.map(fn step_name ->
        case Map.get(plan.steps, step_name) do
          nil ->
            {:error,
             Error.execution_error("Step not found: #{inspect(step_name)}", %{
               type: :step_not_found,
               step_name: step_name
             })}

          plan_instruction ->
            execute_step(plan_instruction, params, context)
        end
      end)

    case Enum.find(step_results, fn result -> match?({:error, _}, result) end) do
      nil ->
        phase_results =
          step_results
          |> Enum.zip(step_names)
          |> Enum.reduce(%{}, fn
            {{:ok, result}, step_name}, acc ->
              Map.put(acc, step_name, result)

            {{:error, _}, _step_name}, acc ->
              acc
          end)

        {:ok, phase_results}

      {:error, reason} ->
        {:error, ensure_error(reason, "Action plan step failed")}
    end
  end

  defp execute_step(plan_instruction, params, context) do
    instruction = plan_instruction.instruction
    action = instruction.action
    merged_params = Map.merge(params, instruction.params)

    case Exec.run(action, merged_params, context, instruction.opts) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error,
         Error.execution_error("Step execution failed", %{
           type: :step_execution_failed,
           step_name: plan_instruction.name,
           reason: ensure_error(reason, "Step execution failed")
         })}

      other ->
        {:error,
         Error.execution_error("Action returned unexpected value: #{inspect(other)}", %{
           type: :invalid_result,
           step_name: plan_instruction.name,
           result: other
         })}
    end
  end
end
