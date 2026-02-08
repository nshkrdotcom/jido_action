defmodule Jido.Exec.Async do
  @moduledoc """
  Handles asynchronous execution of Actions using Task.Supervisor.

  This module provides the core async implementation for Jido.Exec,
  managing task supervision, cleanup, and async lifecycle.
  """
  use Private

  alias Jido.Action.Config
  alias Jido.Action.Error
  alias Jido.Exec.AsyncRef
  alias Jido.Exec.TaskHelper
  alias Jido.Exec.Types

  @flush_timeout_ms 0
  @max_flush_messages 10

  @type action :: Types.action()
  @type params :: Types.params()
  @type context :: Types.context()
  @type run_opts :: Types.run_opts()
  @type async_ref :: Types.async_ref()
  @type async_ref_input :: Types.async_ref_input()
  @type cancel_async_ref_input :: Types.cancel_async_ref_input()
  @type exec_error :: Types.exec_error()
  @type exec_result :: Types.exec_result()

  @doc """
  Starts an asynchronous Action execution.

  This function creates a supervised task that calls back to Jido.Exec.run/4
  to ensure feature consistency across sync and async execution paths.

  ## Parameters

  - `action`: The module implementing the Action behavior.
  - `params`: A map of input parameters for the Action.
  - `context`: A map providing additional context for the Action execution.
  - `opts`: Options controlling the execution (same as Jido.Exec.run/4).
    - `:jido` - Optional instance name for isolation. Routes execution through instance-scoped supervisors.

  ## Returns

  A `%Jido.Exec.AsyncRef{}` struct containing:
  - `:ref` - A unique reference for this async action.
  - `:pid` - The PID of the process executing the Action.
  - `:monitor_ref` - Monitor reference used by the owner process.
  - `:owner` - PID that created the async operation.
  """
  @spec start(action(), params(), context(), run_opts()) :: async_ref()
  def start(action, params \\ %{}, context \\ %{}, opts \\ []) do
    case TaskHelper.spawn_monitored(opts, :action_async_result, fn ->
           Jido.Exec.run(action, params, context, opts)
         end) do
      {:ok, async_ref} ->
        async_ref

      {:error, error} ->
        raise error
    end
  end

  @doc """
  Waits for the result of an asynchronous Action execution.

  ## Parameters

  - `async_ref`: The reference returned by `start/4`.
    Legacy map refs are still accepted for one release cycle and emit a deprecation warning.
  - `timeout`: Maximum time (in ms) to wait for the result (default: configured await timeout).

  ## Returns

  - `{:ok, result}` if the Action executes successfully.
  - `{:error, %Jido.Action.Error.TimeoutError{}}` if the action times out.
  - `{:error, %Jido.Action.Error.ExecutionFailureError{}}` if the process crashes or no result is received.
  """
  @spec await(async_ref_input()) :: exec_result
  def await(async_ref), do: await(async_ref, Config.await_timeout())

  @doc """
  Awaits the completion of an asynchronous Action with a custom timeout.

  ## Parameters

  - `async_ref`: The async reference returned by `start/4`.
    Legacy map refs are still accepted for one release cycle and emit a deprecation warning.
  - `timeout`: Maximum time to wait in milliseconds.

  ## Returns

  - `{:ok, result}` if the Action completes successfully.
  - `{:error, %Jido.Action.Error.TimeoutError{}}` if timeout is reached.
  - `{:error, %Jido.Action.Error.ExecutionFailureError{}}` if an execution failure occurs.
  """
  @spec await(async_ref_input(), timeout()) :: exec_result
  def await(%AsyncRef{ref: ref, pid: pid} = async_ref, timeout) do
    monitor_ref = monitor_ref_for_current_process(async_ref, pid)

    result =
      receive do
        {:action_async_result, ^ref, result} ->
          demonitor(monitor_ref)
          result

        {:DOWN, ^monitor_ref, :process, ^pid, :normal} ->
          # Process completed normally, but result may still be in flight.
          receive do
            {:action_async_result, ^ref, result} ->
              demonitor(monitor_ref)
              result
          after
            Config.async_down_grace_period_ms() ->
              demonitor(monitor_ref)
              {:error, Error.execution_error("Process completed but result was not received")}
          end

        {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
          demonitor(monitor_ref)
          {:error, Error.execution_error("Server error in async action: #{inspect(reason)}")}
      after
        timeout ->
          shutdown_process(pid, monitor_ref)
          flush_messages(ref, pid, monitor_ref, @max_flush_messages)

          {:error,
           Error.timeout_error("Async action timed out after #{timeout}ms", %{timeout: timeout})}
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
  Cancels a running asynchronous Action execution.

  ## Parameters

  - `async_ref`: The reference returned by `start/4`, or just the PID of the process to cancel.
    Legacy map refs are still accepted for one release cycle and emit a deprecation warning.

  ## Returns

  - `:ok` if the cancellation was successful.
  - `{:error, reason}` if the cancellation failed or the input was invalid.
  """
  @spec cancel(cancel_async_ref_input() | pid()) :: :ok | exec_error
  def cancel(%AsyncRef{pid: pid, monitor_ref: monitor_ref}) when is_pid(pid) do
    shutdown_process(pid, monitor_ref)
    :ok
  end

  def cancel(%{pid: pid} = legacy_async_ref)
      when is_pid(pid) and not is_struct(legacy_async_ref, AsyncRef) do
    legacy_async_ref
    |> AsyncRef.from_legacy_cancel_map(__MODULE__)
    |> cancel()
  end

  def cancel(pid) when is_pid(pid) do
    shutdown_process(pid)
    :ok
  end

  def cancel(_), do: {:error, Error.validation_error("Invalid async ref for cancellation")}

  defp monitor_ref_for_current_process(async_ref, pid) do
    cleanup_owner_monitor(async_ref)
    Process.monitor(pid)
  end

  defp cleanup_owner_monitor(async_ref) do
    case {Map.get(async_ref, :owner), Map.get(async_ref, :monitor_ref)} do
      {owner, monitor_ref}
      when is_pid(owner) and owner == self() and is_reference(monitor_ref) ->
        demonitor(monitor_ref)

      _ ->
        :ok
    end
  end

  defp shutdown_process(pid, stale_monitor_ref \\ nil) when is_pid(pid) do
    monitor_ref = Process.monitor(pid)
    Process.exit(pid, :shutdown)

    receive do
      {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
        :ok
    after
      Config.async_shutdown_grace_period_ms() ->
        if Process.alive?(pid), do: Process.exit(pid, :kill)

        receive do
          {:DOWN, ^monitor_ref, :process, ^pid, _reason} -> :ok
        after
          Config.async_down_grace_period_ms() -> :ok
        end
    end

    demonitor(monitor_ref)

    if is_reference(stale_monitor_ref) and stale_monitor_ref != monitor_ref do
      demonitor(stale_monitor_ref)
    end
  end

  defp flush_messages(_ref, _pid, _monitor_ref, 0), do: :ok

  defp flush_messages(ref, pid, monitor_ref, remaining) do
    receive do
      {:action_async_result, ^ref, _} ->
        flush_messages(ref, pid, monitor_ref, remaining - 1)

      {:DOWN, ^monitor_ref, :process, ^pid, _} ->
        flush_messages(ref, pid, monitor_ref, remaining - 1)
    after
      @flush_timeout_ms -> :ok
    end
  end

  defp demonitor(monitor_ref) when is_reference(monitor_ref) do
    Process.demonitor(monitor_ref, [:flush])
    :ok
  end
end
