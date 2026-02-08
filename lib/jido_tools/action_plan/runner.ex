defmodule Jido.Tools.ActionPlan.Runner do
  @moduledoc false

  alias Jido.Action.Error
  alias Jido.Exec
  alias Jido.Plan

  @type plan_execution_result ::
          {:ok, map()}
          | {:ok, map(), any()}
          | {:error, Exception.t()}
          | {:error, Exception.t(), any()}

  @doc """
  Executes a plan by deriving execution phases and running them sequentially.
  """
  def execute_plan(plan, params, context) do
    case Plan.execution_phases(plan) do
      {:ok, phases} ->
        execute_phases(phases, plan, params, context, %{}, nil)

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

      match?({:ok, _, _}, result) ->
        {:ok, elem(result, 1), elem(result, 2)}

      match?({:error, _}, result) ->
        {:error, ensure_error(elem(result, 1), "Result transformation failed")}

      match?({:error, _, _}, result) ->
        {:error, ensure_error(elem(result, 1), "Result transformation failed"), elem(result, 2)}

      true ->
        {:error,
         Error.execution_error("Invalid transform_result return value", %{result: result})}
    end
  end

  @doc """
  Attaches a directive to a normalized transform result.
  """
  @spec attach_directive(plan_execution_result(), any()) :: plan_execution_result()
  def attach_directive({:ok, value}, directive), do: {:ok, value, directive}
  def attach_directive({:error, reason}, directive), do: {:error, reason, directive}

  def attach_directive({:ok, value, existing_directive}, directive) do
    {:ok, value, merge_directives(existing_directive, directive)}
  end

  def attach_directive({:error, reason, existing_directive}, directive) do
    {:error, reason, merge_directives(existing_directive, directive)}
  end

  @doc """
  Wraps an arbitrary reason in an `Error` struct when it isn't one already.
  """
  def ensure_error(reason, message), do: Error.ensure_error(reason, message)

  # -- private helpers -------------------------------------------------------

  defp execute_phases([], _plan, _params, _context, results, nil) do
    {:ok, results}
  end

  defp execute_phases([], _plan, _params, _context, results, directive) do
    {:ok, results, directive}
  end

  defp execute_phases([phase | remaining_phases], plan, params, context, results, directive) do
    case execute_phase(phase, plan, params, context, results) do
      {:ok, phase_results, phase_directive} ->
        updated_results = Map.merge(results, phase_results)

        flattened_results =
          Enum.reduce(phase_results, %{}, fn {_step_name, step_result}, acc ->
            Map.merge(acc, step_result)
          end)

        updated_params = Map.merge(params, flattened_results)
        next_directive = phase_directive || directive

        execute_phases(
          remaining_phases,
          plan,
          updated_params,
          context,
          updated_results,
          next_directive
        )

      {:error, reason} ->
        {:error, ensure_error(reason, "Action plan phase failed")}

      {:error, reason, phase_directive} ->
        {:error, ensure_error(reason, "Action plan phase failed"), phase_directive}
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

    case Enum.find(step_results, &error_result?/1) do
      nil ->
        phase_results =
          step_results
          |> Enum.zip(step_names)
          |> Enum.reduce(%{}, fn
            {{:ok, result}, step_name}, acc ->
              Map.put(acc, step_name, result)

            {{:ok, result, _directive}, step_name}, acc ->
              Map.put(acc, step_name, result)

            {{:error, _}, _step_name}, acc ->
              acc

            {{:error, _, _}, _step_name}, acc ->
              acc
          end)

        {:ok, phase_results, extract_latest_directive(step_results)}

      {:error, reason} ->
        {:error, ensure_error(reason, "Action plan step failed")}

      {:error, reason, directive} ->
        {:error, ensure_error(reason, "Action plan step failed"), directive}
    end
  end

  defp execute_step(plan_instruction, params, context) do
    instruction = plan_instruction.instruction
    action = instruction.action
    merged_params = Map.merge(params, instruction.params)
    exec_result = Exec.run(action, merged_params, context, merge_execution_opts(plan_instruction))
    normalize_step_execution_result(exec_result, plan_instruction)
  end

  defp merge_execution_opts(plan_instruction) do
    plan_opts =
      if Keyword.keyword?(plan_instruction.opts), do: plan_instruction.opts, else: []

    instruction_opts =
      if Keyword.keyword?(plan_instruction.instruction.opts),
        do: plan_instruction.instruction.opts,
        else: []

    Keyword.merge(plan_opts, instruction_opts)
  end

  defp normalize_step_execution_result(exec_result, plan_instruction) do
    case exec_result do
      {:ok, result} ->
        {:ok, result}

      {:ok, result, directive} ->
        {:ok, result, directive}

      {:error, reason} ->
        {:error,
         Error.execution_error("Step execution failed", %{
           type: :step_execution_failed,
           step_name: plan_instruction.name,
           reason: ensure_error(reason, "Step execution failed")
         })}

      {:error, reason, directive} ->
        {:error,
         Error.execution_error("Step execution failed", %{
           type: :step_execution_failed,
           step_name: plan_instruction.name,
           reason: ensure_error(reason, "Step execution failed")
         }), directive}
    end
  end

  defp error_result?({:error, _}), do: true
  defp error_result?({:error, _, _}), do: true
  defp error_result?(_), do: false

  defp extract_latest_directive(step_results) do
    Enum.reduce(step_results, nil, fn
      {:ok, _result, directive}, _acc ->
        directive

      {:error, _reason, directive}, _acc ->
        directive

      _result, acc ->
        acc
    end)
  end

  defp merge_directives(nil, directive), do: directive
  defp merge_directives(directive, nil), do: directive
  defp merge_directives(directive, directive), do: directive

  defp merge_directives(existing_directive, new_directive) do
    %{transform_result: existing_directive, execution: new_directive}
  end
end
