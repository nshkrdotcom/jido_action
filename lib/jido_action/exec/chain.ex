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
  alias Jido.Exec
  alias Jido.Exec.Async
  alias Jido.Exec.TaskHelper
  alias Jido.Exec.Types

  require Logger

  @type chain_action :: module() | {module(), keyword()}
  @type ok_t :: {:ok, any()} | {:error, any()}
  @type chain_async_ref :: Types.async_ref()
  @type chain_sync_result :: {:ok, map()} | {:error, Error.t()} | {:interrupted, map()}
  @type chain_result :: chain_sync_result() | chain_async_ref()
  @type interrupt_check :: (-> boolean())

  @result_tag :chain_async_result
  @down_grace_period_ms 100
  @shutdown_grace_period_ms 1000
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
  - `{:error, error}` if any action in the chain fails.
  - `{:interrupted, result}` if the chain was interrupted, containing the last successful result.
  - Async reference map (`%{ref, pid, monitor_ref, owner}`) if the `:async` option is set to `true`.
  """
  @spec chain([chain_action()], map(), keyword()) :: chain_result()
  def chain(actions, initial_params \\ %{}, opts \\ []) do
    async = Keyword.get(opts, :async, false)
    context = Keyword.get(opts, :context, %{})
    interrupt_check = Keyword.get(opts, :interrupt_check)
    opts = Keyword.drop(opts, [:async, :context, :interrupt_check])

    chain_fun = fn ->
      Enum.reduce_while(actions, {:ok, initial_params}, fn action, {:ok, params} = _acc ->
        maybe_execute_action(action, params, context, opts, interrupt_check)
      end)
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
  """
  @spec await(chain_async_ref()) :: chain_sync_result()
  def await(async_ref), do: await(async_ref, Config.await_timeout())

  @doc """
  Waits for the result of an asynchronous chain execution with a custom timeout.
  """
  @spec await(chain_async_ref(), timeout()) :: chain_sync_result()
  def await(%{ref: ref, pid: pid} = async_ref, timeout) do
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
            @down_grace_period_ms ->
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

  @doc """
  Cancels a running asynchronous chain execution.
  """
  @spec cancel(chain_async_ref() | pid()) :: :ok | {:error, Exception.t()}
  def cancel(async_ref_or_pid), do: Async.cancel(async_ref_or_pid)

  @spec should_interrupt?(interrupt_check | nil) :: boolean()
  defp should_interrupt?(nil), do: false
  defp should_interrupt?(check) when is_function(check, 0), do: check.()

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

  defp shutdown_process(pid, stale_monitor_ref) when is_pid(pid) do
    monitor_ref = Process.monitor(pid)
    Process.exit(pid, :shutdown)

    receive do
      {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
        :ok
    after
      @shutdown_grace_period_ms ->
        if Process.alive?(pid), do: Process.exit(pid, :kill)

        receive do
          {:DOWN, ^monitor_ref, :process, ^pid, _reason} -> :ok
        after
          @down_grace_period_ms -> :ok
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

  @spec maybe_execute_action(chain_action(), map(), map(), keyword(), interrupt_check | nil) ::
          {:cont, ok_t()} | {:halt, chain_result()}
  defp maybe_execute_action(action, params, context, opts, interrupt_check) do
    case should_interrupt?(interrupt_check) do
      true -> handle_interruption(action, params)
      false -> process_action(action, params, context, opts)
    end
  end

  defp handle_interruption(action, params) do
    Logger.info("Chain interrupted before action: #{inspect(action)}")
    {:halt, {:interrupted, params}}
  end

  @spec process_action(chain_action(), map(), map(), keyword()) ::
          {:cont, ok_t()} | {:halt, chain_result()}
  defp process_action(action, params, context, opts) when is_atom(action) do
    run_action(action, params, context, opts)
  end

  @spec process_action({module(), keyword()} | {module(), map()}, map(), map(), keyword()) ::
          {:cont, ok_t()} | {:halt, chain_result()}
  defp process_action({action, action_opts}, params, context, opts)
       when is_atom(action) and (is_list(action_opts) or is_map(action_opts)) do
    case validate_action_params(action_opts) do
      {:ok, action_params} ->
        merged_params = Map.merge(params, action_params)
        run_action(action, merged_params, context, opts)

      {:error, error} ->
        {:halt, {:error, error}}
    end
  end

  @spec process_action(any(), map(), map(), keyword()) :: {:halt, {:error, Error.t()}}
  defp process_action(invalid_action, _params, _context, _opts) do
    {:halt, {:error, Error.validation_error("Invalid chain action", %{action: invalid_action})}}
  end

  @spec validate_action_params(keyword() | map()) :: ok_t()
  defp validate_action_params(opts) when is_list(opts) do
    if Enum.all?(opts, fn {k, _v} -> is_atom(k) end) do
      {:ok, Map.new(opts)}
    else
      {:error, Error.validation_error("Exec parameters must use atom keys")}
    end
  end

  defp validate_action_params(opts) when is_map(opts) do
    if Enum.all?(Map.keys(opts), &is_atom/1) do
      {:ok, opts}
    else
      {:error, Error.validation_error("Exec parameters must use atom keys")}
    end
  end

  @spec run_action(module(), map(), map(), keyword()) ::
          {:cont, ok_t()} | {:halt, chain_result()}
  defp run_action(action, params, context, opts) do
    case Exec.run(action, params, context, opts) do
      {:ok, result} when is_map(result) ->
        {:cont, {:ok, Map.merge(params, result)}}

      {:ok, result, _directive} when is_map(result) ->
        {:cont, {:ok, Map.merge(params, result)}}

      {:error, error} ->
        Logger.warning("Exec in chain failed: #{inspect(action)} #{inspect(error)}")
        {:halt, {:error, error}}

      {:error, error, _directive} ->
        Logger.warning("Exec in chain failed: #{inspect(action)} #{inspect(error)}")
        {:halt, {:error, error}}
    end
  end
end
