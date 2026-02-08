defmodule Jido.Tools.Workflow.Execution do
  @moduledoc false

  alias Jido.Action.Config
  alias Jido.Action.Error
  alias Jido.Action.Util
  alias Jido.Exec
  alias Jido.Exec.Supervisors
  alias Jido.Instruction

  @workflow_task_supervisor_key :__jido_workflow_task_supervisor__
  @workflow_deadline_key :__jido_workflow_deadline_ms__
  @exec_deadline_key :__jido_exec_deadline_ms__

  @type execution_result ::
          {:ok, map()}
          | {:ok, map(), any()}
          | {:error, Exception.t()}
          | {:error, Exception.t(), any()}

  @spec execute_workflow(list(), map(), map(), module()) :: execution_result()
  def execute_workflow(steps, params, context, module) do
    runtime_context = enrich_workflow_runtime_context(context)
    initial_acc = {:ok, params, %{}, nil}

    steps
    |> Enum.reduce_while(initial_acc, &reduce_step(&1, &2, runtime_context, module))
    |> case do
      {:ok, _final_params, final_results, nil} -> {:ok, final_results}
      {:ok, _final_params, final_results, directive} -> {:ok, final_results, directive}
      {:error, reason} -> {:error, ensure_error(reason)}
      {:error, reason, directive} -> {:error, ensure_error(reason), directive}
    end
  end

  defp reduce_step(step, {_status, current_params, results, current_directive}, context, module) do
    case ensure_workflow_time_remaining(context) do
      :ok ->
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

      {:error, timeout_error} ->
        {:halt, {:error, timeout_error}}
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
    {workflow_task_supervisor, workflow_deadline_ms, sanitized_context} =
      extract_workflow_runtime_context(context)

    remaining_timeout_ms = remaining_timeout_ms(workflow_deadline_ms)
    merged_params = Map.merge(params, normalized.params)
    merged_context = Map.merge(normalized.context, sanitized_context)

    case remaining_timeout_ms do
      0 ->
        {:error, workflow_timeout_error(0)}

      _ ->
        instruction_opts =
          default_internal_retry_opts(
            normalized.opts,
            workflow_task_supervisor,
            remaining_timeout_ms
          )

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
  end

  defp default_internal_retry_opts(opts, workflow_task_supervisor, remaining_timeout_ms)
       when is_list(opts) do
    if Keyword.keyword?(opts) do
      opts
      |> maybe_put_default(:max_retries, 0)
      |> maybe_put_task_supervisor(workflow_task_supervisor)
      |> apply_workflow_timeout_budget(remaining_timeout_ms)
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

  defp apply_workflow_timeout_budget(opts, nil) do
    if Keyword.has_key?(opts, :timeout) do
      opts
    else
      Keyword.put(opts, :timeout, Config.exec_timeout())
    end
  end

  defp apply_workflow_timeout_budget(opts, remaining_timeout_ms)
       when is_integer(remaining_timeout_ms) and remaining_timeout_ms > 0 do
    bounded_timeout =
      case Keyword.get(opts, :timeout) do
        :infinity ->
          remaining_timeout_ms

        timeout when is_integer(timeout) and timeout > 0 ->
          min(timeout, remaining_timeout_ms)

        _ ->
          remaining_timeout_ms
      end

    Keyword.put(opts, :timeout, bounded_timeout)
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
    ordered = Keyword.get(metadata, :ordered, false)
    owner = self()

    if timeout == 0 do
      {:error, workflow_timeout_error(0)}
    else
      with_parallel_task_supervisor(metadata, context, fn task_sup ->
        execute_parallel_with_supervisor(
          task_sup,
          instructions,
          params,
          context,
          module,
          max_concurrency: max_concurrency,
          timeout: timeout,
          ordered: ordered,
          owner: owner
        )
      end)
    end
  end

  defp execute_parallel_with_supervisor(
         task_sup,
         instructions,
         params,
         context,
         module,
         opts
       ) do
    scoped_context = Map.put(context, @workflow_task_supervisor_key, task_sup)

    stream_opts = [
      ordered: Keyword.fetch!(opts, :ordered),
      max_concurrency: Keyword.fetch!(opts, :max_concurrency),
      timeout: Keyword.fetch!(opts, :timeout),
      on_timeout: :kill_task
    ]

    owner = Keyword.fetch!(opts, :owner)

    results =
      stream_parallel_instructions(
        task_sup,
        instructions,
        params,
        scoped_context,
        module,
        owner,
        stream_opts
      )

    {:ok, %{parallel_results: results}}
  end

  defp stream_parallel_instructions(
         task_sup,
         instructions,
         params,
         scoped_context,
         module,
         owner,
         stream_opts
       ) do
    Task.Supervisor.async_stream_nolink(
      task_sup,
      instructions,
      fn instruction ->
        execute_parallel_instruction_with_owner_watchdog(
          instruction,
          params,
          scoped_context,
          module,
          owner
        )
      end,
      stream_opts
    )
    |> Enum.map(&handle_stream_result/1)
  end

  defp handle_stream_result({:ok, value}), do: value

  defp handle_stream_result({:exit, reason}) do
    %{error: Error.execution_error("Parallel task exited", %{reason: reason})}
  end

  defp execute_parallel_instruction_with_owner_watchdog(
         instruction,
         params,
         context,
         module,
         owner
       ) do
    watcher_pid = spawn_owner_watcher(owner, self())

    try do
      execute_parallel_instruction(instruction, params, context, module)
    after
      Process.exit(watcher_pid, :kill)
    end
  end

  defp spawn_owner_watcher(owner, task_pid) when is_pid(owner) and is_pid(task_pid) do
    spawn(fn ->
      monitor_ref = Process.monitor(owner)

      receive do
        {:DOWN, ^monitor_ref, :process, ^owner, _reason} ->
          Process.exit(task_pid, :kill)
      end
    end)
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
    base_timeout =
      Util.first_present(
        [
          metadata_timeout(metadata),
          context_timeout(context)
        ],
        Config.exec_timeout()
      )

    base_timeout
    |> normalize_timeout()
    |> cap_timeout_by_workflow_deadline(remaining_timeout_ms(context))
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

  defp with_parallel_task_supervisor(metadata, context, fun)
       when is_list(metadata) and is_function(fun, 1) do
    opts = build_parallel_supervisor_opts(metadata, context)

    case opts do
      [] ->
        case Task.Supervisor.start_link() do
          {:ok, task_sup} ->
            try do
              fun.(task_sup)
            after
              stop_parallel_supervisor(task_sup)
            end

          {:error, reason} ->
            {:error,
             Error.execution_error("Failed to start parallel task supervisor", %{reason: reason})}
        end

      _ ->
        case resolve_task_supervisor(opts) do
          {:ok, task_sup} ->
            fun.(task_sup)

          {:error, reason} ->
            {:error, ensure_error(reason)}
        end
    end
  end

  defp resolve_task_supervisor(opts) when is_list(opts) do
    {:ok, Supervisors.task_supervisor(opts)}
  rescue
    e in ArgumentError -> {:error, e}
  end

  defp stop_parallel_supervisor(task_sup) when is_pid(task_sup) do
    Supervisor.stop(task_sup, :normal)
  catch
    :exit, {:noproc, _} -> :ok
  end

  defp build_parallel_supervisor_opts(metadata, context) do
    explicit_task_supervisor =
      Util.first_present([
        Keyword.get(metadata, :task_supervisor),
        metadata_task_supervisor(context),
        Map.get(context, @workflow_task_supervisor_key)
      ])

    case explicit_task_supervisor do
      nil ->
        case Util.first_present([
               Keyword.get(metadata, :jido),
               context_jido(context)
             ]) do
          nil -> []
          jido -> [jido: jido]
        end

      task_supervisor ->
        [task_supervisor: task_supervisor]
    end
  end

  defp metadata_task_supervisor(context) when is_map(context) do
    Util.first_present([
      Map.get(context, :task_supervisor),
      Map.get(context, "task_supervisor")
    ])
  end

  defp metadata_task_supervisor(_), do: nil

  defp context_jido(context) when is_map(context) do
    Util.first_present([
      Map.get(context, :__jido__),
      Map.get(context, "__jido__"),
      Map.get(context, :jido),
      Map.get(context, "jido")
    ])
  end

  defp cap_timeout_by_workflow_deadline(timeout, nil), do: timeout

  defp cap_timeout_by_workflow_deadline(_timeout, 0), do: 0

  defp cap_timeout_by_workflow_deadline(:infinity, remaining_timeout_ms),
    do: remaining_timeout_ms

  defp cap_timeout_by_workflow_deadline(timeout, remaining_timeout_ms)
       when is_integer(timeout) and is_integer(remaining_timeout_ms) do
    min(timeout, remaining_timeout_ms)
  end

  defp extract_workflow_runtime_context(context) when is_map(context) do
    workflow_task_supervisor = Map.get(context, @workflow_task_supervisor_key)
    workflow_deadline_ms = Map.get(context, @workflow_deadline_key)

    sanitized_context =
      context
      |> Map.delete(@workflow_task_supervisor_key)
      |> Map.delete(@workflow_deadline_key)
      |> Map.delete(@exec_deadline_key)

    {workflow_task_supervisor, workflow_deadline_ms, sanitized_context}
  end

  defp extract_workflow_runtime_context(context), do: {nil, nil, context}

  defp enrich_workflow_runtime_context(context) when is_map(context) do
    case resolve_workflow_deadline(context) do
      nil -> context
      deadline_ms -> Map.put(context, @workflow_deadline_key, deadline_ms)
    end
  end

  defp enrich_workflow_runtime_context(context), do: context

  defp resolve_workflow_deadline(context) when is_map(context) do
    current_deadline =
      Util.first_present([
        Map.get(context, @workflow_deadline_key),
        Map.get(context, @exec_deadline_key)
      ])

    case current_deadline do
      deadline when is_integer(deadline) ->
        deadline

      _ ->
        Util.first_present([
          Map.get(context, :workflow_timeout),
          Map.get(context, "workflow_timeout"),
          Map.get(context, :timeout),
          Map.get(context, "timeout")
        ])
        |> timeout_to_deadline()
    end
  end

  defp timeout_to_deadline(timeout) when is_integer(timeout) and timeout > 0 do
    System.monotonic_time(:millisecond) + timeout
  end

  defp timeout_to_deadline(_), do: nil

  defp ensure_workflow_time_remaining(context) do
    case remaining_timeout_ms(context) do
      0 -> {:error, workflow_timeout_error(0)}
      _ -> :ok
    end
  end

  defp remaining_timeout_ms(context) when is_map(context) do
    remaining_timeout_ms(Map.get(context, @workflow_deadline_key))
  end

  defp remaining_timeout_ms(deadline_ms) when is_integer(deadline_ms) do
    max(deadline_ms - System.monotonic_time(:millisecond), 0)
  end

  defp remaining_timeout_ms(_), do: nil

  defp workflow_timeout_error(timeout_ms) do
    Error.timeout_error("Workflow deadline exceeded before step execution", %{
      timeout: timeout_ms
    })
  end

  defp ensure_error(reason), do: Error.ensure_error(reason, "Workflow step failed")
end
