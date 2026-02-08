defmodule Jido.Exec.Chain do
  @moduledoc """
  Provides functionality to chain multiple Jido Execs together with interruption support.

  This module allows for sequential execution of actions, where the output
  of one action becomes the input for the next action in the chain.
  Execution can be interrupted between actions using an interruption check function.

  ## Examples

      iex> interrupt_check = fn -> System.monotonic_time(:millisecond) > @deadline end
      iex> Jido.Exec.Chain.chain([AddOne, MultiplyByTwo], %{value: 5}, interrupt_check: interrupt_check)
      {:ok, %{value: 12}}

      # When interrupted:
      iex> Jido.Exec.Chain.chain([AddOne, MultiplyByTwo], %{value: 5}, interrupt_check: fn -> true end)
      {:interrupted, %{value: 6}}
  """

  alias Jido.Action.Config
  alias Jido.Action.Error
  alias Jido.Action.Params
  alias Jido.Exec
  alias Jido.Exec.Async
  alias Jido.Exec.AsyncRef
  alias Jido.Exec.TaskHelper
  alias Jido.Exec.Types

  require Logger

  @type chain_action :: module() | {module(), any()}
  @type chain_ok :: {:ok, map()} | {:ok, map(), any()}
  @type chain_error :: {:error, Error.t()} | {:error, Error.t(), any()}
  @type ok_t :: chain_ok() | chain_error()
  @type chain_async_ref :: Types.async_ref()
  @type chain_async_ref_input :: Types.async_ref_input()
  @type chain_cancel_input :: Types.cancel_async_ref_input()
  @type chain_sync_result :: chain_ok() | chain_error() | {:interrupted, map()}
  @type chain_result :: chain_sync_result() | chain_async_ref()
  @type interrupt_check :: (-> boolean())

  @result_tag :chain_async_result
  @flush_timeout_ms 0
  @max_flush_messages 10

  @doc """
  Executes a chain of actions sequentially with optional interruption support.

  ## Parameters

  - `actions`: A list of actions to be executed in order. Each action
    can be a module (the action module) or a tuple of `{action_module, options}`.
  - `initial_params`: A map of initial parameters to be passed to the first action.
  - `opts`: Additional options for the chain execution.

  ## Options

  - `:async` - When set to `true`, the chain will be executed asynchronously (default: `false`).
  - `:context` - A map of context data to be passed to each action.
  - `:interrupt_check` - A function that returns boolean, called between actions to check if chain should be interrupted.

  ## Returns

  - `{:ok, result}` where `result` is the final output of the chain.
  - `{:ok, result, directive}` when the final successful action emits a directive.
  - `{:error, error}` if any action in the chain fails.
  - `{:error, error, directive}` if a failing action returns an error directive.
  - `{:interrupted, result}` if the chain was interrupted, containing the last successful result.
  - `%Jido.Exec.AsyncRef{}` if the `:async` option is set to `true`.
  """
  @spec chain([chain_action()], map(), keyword()) :: chain_result()
  def chain(actions, initial_params \\ %{}, opts \\ []) do
    async = Keyword.get(opts, :async, false)
    context = Keyword.get(opts, :context, %{})
    interrupt_check = Keyword.get(opts, :interrupt_check)
    opts = Keyword.drop(opts, [:async, :context, :interrupt_check])

    chain_fun = fn ->
      actions
      |> Enum.reduce_while({:ok, initial_params, nil}, fn action, {:ok, params, directive} ->
        maybe_execute_action(action, params, directive, context, opts, interrupt_check)
      end)
      |> finalize_chain_result()
    end

    if async do
      case TaskHelper.spawn_monitored(opts, @result_tag, chain_fun) do
        {:ok, async_ref} -> async_ref
        {:error, error} -> raise error
      end
    else
      chain_fun.()
    end
  end

  @doc """
  Waits for the result of an asynchronous chain execution.

  Legacy map refs are still accepted for one release cycle and emit a deprecation warning.
  """
  @spec await(chain_async_ref_input()) :: chain_sync_result()
  def await(async_ref), do: await(async_ref, Config.await_timeout())

  @doc """
  Waits for the result of an asynchronous chain execution with a custom timeout.

  Legacy map refs are still accepted for one release cycle and emit a deprecation warning.
  """
  @spec await(chain_async_ref_input(), timeout()) :: chain_sync_result()
  def await(%AsyncRef{ref: ref, pid: pid} = async_ref, timeout) do
    monitor_ref = monitor_ref_for_current_process(async_ref, pid)

    result =
      receive do
        {@result_tag, ^ref, result} ->
          TaskHelper.demonitor_flush(monitor_ref)
          result

        {:DOWN, ^monitor_ref, :process, ^pid, :normal} ->
          receive do
            {@result_tag, ^ref, result} ->
              TaskHelper.demonitor_flush(monitor_ref)
              result
          after
            Config.chain_down_grace_period_ms() ->
              TaskHelper.demonitor_flush(monitor_ref)
              {:error, Error.execution_error("Chain completed but result was not received")}
          end

        {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
          TaskHelper.demonitor_flush(monitor_ref)
          {:error, Error.execution_error("Server error in async chain: #{inspect(reason)}")}
      after
        timeout ->
          shutdown_process(pid, monitor_ref)
          flush_messages(ref, pid, monitor_ref, @max_flush_messages)

          {:error,
           Error.timeout_error("Async chain timed out after #{timeout}ms", %{timeout: timeout})}
      end

    flush_messages(ref, pid, monitor_ref, @max_flush_messages)
    result
  end

  def await(%{ref: ref, pid: pid} = legacy_async_ref, timeout)
      when is_reference(ref) and is_pid(pid) and not is_struct(legacy_async_ref, AsyncRef) do
    legacy_async_ref
    |> AsyncRef.from_legacy_await_map(__MODULE__)
    |> await(timeout)
  end

  @doc """
  Cancels a running asynchronous chain execution.

  Legacy map refs are still accepted for one release cycle and emit a deprecation warning.
  """
  @spec cancel(chain_cancel_input() | pid()) :: :ok | {:error, Exception.t()}
  def cancel(%{pid: pid} = legacy_async_ref)
      when is_pid(pid) and not is_struct(legacy_async_ref, AsyncRef) do
    legacy_async_ref
    |> AsyncRef.from_legacy_cancel_map(__MODULE__)
    |> Async.cancel()
  end

  def cancel(async_ref_or_pid), do: Async.cancel(async_ref_or_pid)

  defp monitor_ref_for_current_process(async_ref, pid) do
    cleanup_owner_monitor(async_ref)
    Process.monitor(pid)
  end

  defp cleanup_owner_monitor(async_ref) do
    case {Map.get(async_ref, :owner), Map.get(async_ref, :monitor_ref)} do
      {owner, monitor_ref}
      when is_pid(owner) and owner == self() and is_reference(monitor_ref) ->
        TaskHelper.demonitor_flush(monitor_ref)

      _ ->
        :ok
    end
  end

  @dialyzer {:nowarn_function, shutdown_process: 2}
  defp shutdown_process(pid, stale_monitor_ref) when is_pid(pid) do
    monitor_ref = Process.monitor(pid)
    Process.exit(pid, :shutdown)

    receive do
      {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
        :ok
    after
      Config.chain_shutdown_grace_period_ms() ->
        if Process.alive?(pid), do: Process.exit(pid, :kill)

        receive do
          {:DOWN, ^monitor_ref, :process, ^pid, _reason} -> :ok
        after
          Config.chain_down_grace_period_ms() -> :ok
        end
    end

    TaskHelper.demonitor_flush(monitor_ref)

    if is_reference(stale_monitor_ref) and stale_monitor_ref != monitor_ref do
      TaskHelper.demonitor_flush(stale_monitor_ref)
    end
  end

  defp flush_messages(_ref, _pid, _monitor_ref, 0), do: :ok

  defp flush_messages(ref, pid, monitor_ref, remaining) do
    receive do
      {@result_tag, ^ref, _result} ->
        flush_messages(ref, pid, monitor_ref, remaining - 1)

      {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
        flush_messages(ref, pid, monitor_ref, remaining - 1)
    after
      @flush_timeout_ms -> :ok
    end
  end

  @spec maybe_execute_action(
          chain_action(),
          map(),
          any() | nil,
          map(),
          keyword(),
          interrupt_check() | nil
        ) ::
          {:cont, ok_t()} | {:halt, chain_result()}
  defp maybe_execute_action(action, params, current_directive, context, opts, nil) do
    process_action(action, params, current_directive, context, opts)
  end

  defp maybe_execute_action(action, params, current_directive, context, opts, interrupt_check)
       when is_function(interrupt_check, 0) do
    if interrupt_check.() do
      Logger.info("Chain interrupted before action: #{inspect(action)}")
      {:halt, {:interrupted, params}}
    else
      process_action(action, params, current_directive, context, opts)
    end
  end

  @spec process_action(chain_action(), map(), any() | nil, map(), keyword()) ::
          {:cont, ok_t()} | {:halt, chain_result()}
  defp process_action(action, params, current_directive, context, opts) when is_atom(action) do
    run_action(action, params, current_directive, context, opts)
  end

  @spec process_action(
          {module(), any()},
          map(),
          any() | nil,
          map(),
          keyword()
        ) ::
          {:cont, ok_t()} | {:halt, chain_result()}
  @dialyzer {:nowarn_function, process_action: 5}
  defp process_action({action, action_opts}, params, current_directive, context, opts)
       when is_atom(action) do
    case normalize_action_params(action_opts) do
      {:ok, action_params} ->
        merged_params = Map.merge(params, action_params)
        run_action(action, merged_params, current_directive, context, opts)

      {:error, error} ->
        {:halt, {:error, error}}
    end
  end

  @spec process_action(any(), map(), any() | nil, map(), keyword()) ::
          {:halt, {:error, Error.t()}}
  defp process_action(invalid_action, _params, _current_directive, _context, _opts) do
    {:halt, {:error, Error.validation_error("Invalid chain action", %{action: invalid_action})}}
  end

  @spec normalize_action_params(any()) :: {:ok, map()} | {:error, Error.t()}
  defp normalize_action_params(nil) do
    {:error, Error.validation_error("Exec parameters must be a map or keyword list")}
  end

  defp normalize_action_params(opts) do
    case Params.normalize_instruction_params(opts) do
      {:ok, normalized} ->
        with :ok <- ensure_atom_param_keys(normalized) do
          {:ok, normalized}
        end

      {:error, %_{} = error} when is_exception(error) ->
        {:error, Error.validation_error(Exception.message(error), %{reason: error})}
    end
  end

  @spec ensure_atom_param_keys(map()) :: :ok | {:error, Error.t()}
  defp ensure_atom_param_keys(params) when is_map(params) do
    if Enum.all?(Map.keys(params), &is_atom/1) do
      :ok
    else
      {:error, Error.validation_error("Exec parameters must use atom keys")}
    end
  end

  @spec run_action(module(), map(), any() | nil, map(), keyword()) ::
          {:cont, ok_t()} | {:halt, chain_result()}
  defp run_action(action, params, current_directive, context, opts) do
    case Exec.run(action, params, context, opts) do
      {:ok, result} when is_map(result) ->
        {:cont, {:ok, Map.merge(params, result), current_directive}}

      {:ok, result, directive} when is_map(result) ->
        {:cont, {:ok, Map.merge(params, result), directive}}

      {:error, error} ->
        Logger.warning("Exec in chain failed: #{inspect(action)} #{inspect(error)}")
        {:halt, {:error, error}}

      {:error, error, directive} ->
        Logger.warning("Exec in chain failed: #{inspect(action)} #{inspect(error)}")
        {:halt, {:error, error, directive}}
    end
  end

  defp finalize_chain_result({:ok, params, nil}), do: {:ok, params}
  defp finalize_chain_result({:ok, params, directive}), do: {:ok, params, directive}
  defp finalize_chain_result(other), do: other
end
