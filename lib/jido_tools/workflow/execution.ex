defmodule Jido.Tools.Workflow.Execution do
  @moduledoc false

  alias Jido.Action.Config
  alias Jido.Action.Error
  alias Jido.Action.Util
  alias Jido.Exec
  alias Jido.Instruction

  @workflow_task_supervisor_key :__jido_workflow_task_supervisor__

  @type execution_result ::
          {:ok, map()}
          | {:ok, map(), any()}
          | {:error, Exception.t()}
          | {:error, Exception.t(), any()}

  @spec execute_workflow(list(), map(), map(), module()) :: execution_result()
  def execute_workflow(steps, params, context, module) do
    initial_acc = {:ok, params, %{}, nil}

    steps
    |> Enum.reduce_while(initial_acc, &reduce_step(&1, &2, context, module))
    |> case do
      {:ok, _final_params, final_results, nil} -> {:ok, final_results}
      {:ok, _final_params, final_results, directive} -> {:ok, final_results, directive}
      {:error, reason} -> {:error, ensure_error(reason)}
      {:error, reason, directive} -> {:error, ensure_error(reason), directive}
    end
  end

  defp reduce_step(step, {_status, current_params, results, current_directive}, context, module) do
    case module.execute_step(step, current_params, context) do
      {:ok, step_result} when is_map(step_result) ->
        updated_results = Map.merge(results, step_result)
        updated_params = Map.merge(current_params, step_result)
        {:cont, {:ok, updated_params, updated_results, current_directive}}

      {:ok, step_result, directive} when is_map(step_result) ->
        updated_results = Map.merge(results, step_result)
        updated_params = Map.merge(current_params, step_result)
        {:cont, {:ok, updated_params, updated_results, directive}}

      {:ok, step_result} ->
        {:halt,
         {:error,
          Error.execution_error("Expected map, got: #{inspect(step_result)}", %{
            type: :invalid_step_result,
            step_result: step_result
          })}}

      {:error, reason} ->
        {:halt, {:error, ensure_error(reason)}}

      {:error, reason, directive} ->
        {:halt, {:error, ensure_error(reason), directive}}
    end
  end

  @doc false
  @spec execute_step(tuple(), map(), map(), module()) ::
          {:ok, any()} | {:ok, any(), any()} | {:error, any()} | {:error, any(), any()}
  def execute_step(step, params, context, module) do
    case step do
      {:step, _metadata, [instruction]} ->
        execute_instruction(instruction, params, context)

      {:branch, metadata, [condition, true_branch, false_branch]} ->
        execute_branch(condition, true_branch, false_branch, params, context, metadata, module)

      {:converge, _metadata, [instruction]} ->
        execute_instruction(instruction, params, context)

      {:parallel, metadata, instructions} ->
        execute_parallel(instructions, params, context, metadata, module)

      _ ->
        {:error,
         Error.validation_error("Unknown step type: #{inspect(step)}", %{
           type: :invalid_step,
           step: step
         })}
    end
  end

  defp execute_instruction(instruction, params, context) do
    case Instruction.normalize_single(instruction) do
      {:ok, %Instruction{} = normalized} ->
        run_normalized_instruction(normalized, params, context)

      {:error, reason} ->
        {:error,
         Error.validation_error("Failed to normalize instruction: #{inspect(reason)}", %{
           type: :invalid_instruction,
           reason: reason
         })}
    end
  end

  defp run_normalized_instruction(%Instruction{} = normalized, params, context) do
    {workflow_task_supervisor, sanitized_context} = extract_workflow_task_supervisor(context)
    merged_params = Map.merge(params, normalized.params)
    merged_context = Map.merge(normalized.context, sanitized_context)
    instruction_opts = default_internal_retry_opts(normalized.opts, workflow_task_supervisor)

    instruction = %{
      normalized
      | params: merged_params,
        context: merged_context,
        opts: instruction_opts
    }

    case Exec.run(instruction) do
      {:ok, result} ->
        {:ok, result}

      {:ok, result, directive} ->
        {:ok, result, directive}

      {:error, reason} ->
        {:error, ensure_error(reason)}

      {:error, reason, directive} ->
        {:error, ensure_error(reason), directive}
    end
  end

  defp default_internal_retry_opts(opts, workflow_task_supervisor) when is_list(opts) do
    if Keyword.keyword?(opts) do
      opts
      |> maybe_put_default(:max_retries, 0)
      |> maybe_put_default(:timeout, Config.exec_timeout())
      |> maybe_put_task_supervisor(workflow_task_supervisor)
    else
      opts
    end
  end

  defp maybe_put_default(opts, key, value) when is_list(opts) and is_atom(key) do
    if Keyword.has_key?(opts, key), do: opts, else: Keyword.put(opts, key, value)
  end

  defp maybe_put_task_supervisor(opts, nil), do: opts

  defp maybe_put_task_supervisor(opts, workflow_task_supervisor) do
    if Keyword.has_key?(opts, :task_supervisor) or Keyword.has_key?(opts, :jido) do
      opts
    else
      Keyword.put(opts, :task_supervisor, workflow_task_supervisor)
    end
  end

  defp execute_branch(condition, true_branch, false_branch, params, context, _metadata, module)
       when is_boolean(condition) do
    if condition do
      module.execute_step(true_branch, params, context)
    else
      module.execute_step(false_branch, params, context)
    end
  end

  defp execute_branch(
         _condition,
         _true_branch,
         _false_branch,
         _params,
         _context,
         metadata,
         _module
       ) do
    {:error,
     Error.validation_error("Invalid or unhandled condition in branch #{inspect(metadata)}", %{
       type: :invalid_condition,
       metadata: metadata
     })}
  end

  defp execute_parallel(instructions, params, context, metadata, module) do
    max_concurrency = Keyword.get(metadata, :max_concurrency, System.schedulers_online())
    timeout = resolve_parallel_timeout(metadata, context)

    # Scope parallel child tasks under a supervisor linked to this workflow process.
    # If the workflow is terminated (for example on timeout), this supervisor exits,
    # ensuring in-flight parallel tasks are also terminated.
    case Task.Supervisor.start_link() do
      {:ok, task_sup} ->
        try do
          scoped_context = Map.put(context, @workflow_task_supervisor_key, task_sup)

          stream_opts = [
            ordered: true,
            max_concurrency: max_concurrency,
            timeout: timeout,
            on_timeout: :kill_task
          ]

          results =
            Task.Supervisor.async_stream_nolink(
              task_sup,
              instructions,
              fn instruction ->
                execute_parallel_instruction(instruction, params, scoped_context, module)
              end,
              stream_opts
            )
            |> Enum.map(&handle_stream_result/1)

          {:ok, %{parallel_results: results}}
        after
          stop_parallel_supervisor(task_sup)
        end

      {:error, reason} ->
        {:error,
         Error.execution_error("Failed to start parallel task supervisor", %{reason: reason})}
    end
  end

  defp handle_stream_result({:ok, value}), do: value

  defp handle_stream_result({:exit, reason}) do
    %{error: Error.execution_error("Parallel task exited", %{reason: reason})}
  end

  defp execute_parallel_instruction(instruction, params, context, module) do
    case module.execute_step(instruction, params, context) do
      {:ok, result} -> result
      {:ok, result, directive} -> %{result: result, directive: directive}
      {:error, reason} -> %{error: ensure_error(reason)}
      {:error, reason, directive} -> %{error: ensure_error(reason), directive: directive}
    end
  rescue
    e ->
      %{error: Error.execution_error("Parallel step raised", %{exception: e})}
  catch
    kind, reason ->
      %{error: Error.execution_error("Parallel step caught", %{kind: kind, reason: reason})}
  end

  defp resolve_parallel_timeout(metadata, context) do
    timeout =
      Util.first_present(
        [
          metadata_timeout(metadata),
          context_timeout(context)
        ],
        Config.exec_timeout()
      )

    normalize_timeout(timeout)
  end

  @spec metadata_timeout(Keyword.t()) :: non_neg_integer() | :infinity | nil
  defp metadata_timeout(metadata) when is_list(metadata) do
    Util.first_present([
      Keyword.get(metadata, :parallel_timeout),
      Keyword.get(metadata, :timeout)
    ])
  end

  defp context_timeout(context) when is_map(context) do
    Util.first_present([
      Map.get(context, :parallel_timeout),
      Map.get(context, "parallel_timeout")
    ])
  end

  defp context_timeout(_), do: nil

  defp normalize_timeout(:infinity), do: :infinity
  defp normalize_timeout(timeout) when is_integer(timeout) and timeout >= 0, do: timeout
  defp normalize_timeout(_invalid), do: Config.exec_timeout()

  defp stop_parallel_supervisor(task_sup) do
    Supervisor.stop(task_sup, :normal)
  catch
    :exit, {:noproc, _} -> :ok
  end

  defp extract_workflow_task_supervisor(context) when is_map(context) do
    {Map.get(context, @workflow_task_supervisor_key),
     Map.delete(context, @workflow_task_supervisor_key)}
  end

  defp extract_workflow_task_supervisor(context), do: {nil, context}

  defp ensure_error(reason), do: Error.ensure_error(reason, "Workflow step failed")
end
