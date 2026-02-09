defmodule Jido.Exec.Async do
  @moduledoc """
  Handles asynchronous execution of Actions using Task.Supervisor.

  This module provides the core async implementation for Jido.Exec, 
  managing task supervision, cleanup, and async lifecycle.
  """
  use Private

  alias Jido.Action.Error
  alias Jido.Exec.Supervisors
  alias Jido.Exec.TaskHelper

  @default_timeout 5000

  # Helper functions to get configuration values with fallbacks
  defp get_default_timeout do
    case Application.get_env(:jido_action, :default_timeout, @default_timeout) do
      timeout when is_integer(timeout) and timeout >= 0 -> timeout
      _ -> @default_timeout
    end
  end

  @type action :: module()
  @type params :: map()
  @type context :: map()
  @type run_opts :: [timeout: non_neg_integer(), jido: atom()]
  @type async_ref :: %{ref: reference(), pid: pid()}

  # Execution result types
  @type exec_success :: {:ok, map()}
  @type exec_success_dir :: {:ok, map(), any()}
  @type exec_error :: {:error, Exception.t()}
  @type exec_error_dir :: {:error, Exception.t(), any()}

  @type exec_result ::
          exec_success
          | exec_success_dir
          | exec_error
          | exec_error_dir

  @monitor_key_prefix {__MODULE__, :monitor_ref}
  @pid_monitor_key_prefix {__MODULE__, :pid_monitor_ref}

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

  An `async_ref` map containing:
  - `:ref` - A unique reference for this async action.
  - `:pid` - The PID of the process executing the Action.
  """
  @spec start(action(), params(), context(), run_opts()) :: async_ref()
  def start(action, params \\ %{}, context \\ %{}, opts \\ []) do
    # Resolve supervisor based on jido: option (defaults to global)
    task_sup = Supervisors.task_supervisor(opts)

    case TaskHelper.spawn_monitored(
           task_sup,
           fn -> Jido.Exec.run(action, params, context, opts) end,
           :action_async_result
         ) do
      {:ok, %{pid: pid, ref: ref, monitor_ref: monitor_ref}} ->
        put_monitor_ref(ref, pid, monitor_ref)
        %{pid: pid, ref: ref}

      {:error, reason} ->
        raise ArgumentError,
              "Failed to start async task under #{inspect(task_sup)}: #{inspect(reason)}"
    end
  end

  @doc """
  Waits for the result of an asynchronous Action execution.

  ## Parameters

  - `async_ref`: The reference returned by `start/4`.
  - `timeout`: Maximum time (in ms) to wait for the result (default: 5000).

  ## Returns

  - `{:ok, result}` if the Action executes successfully.
  - `{:error, reason}` if an error occurs during execution or if the action times out.
  """
  @spec await(async_ref()) :: exec_result
  def await(async_ref), do: await(async_ref, get_default_timeout())

  @doc """
  Awaits the completion of an asynchronous Action with a custom timeout.

  ## Parameters

  - `async_ref`: The async reference returned by `start/4`.
  - `timeout`: Maximum time to wait in milliseconds.

  ## Returns

  - `{:ok, result}` if the Action completes successfully.
  - `{:error, reason}` if an error occurs or timeout is reached.
  """
  @spec await(async_ref(), timeout()) :: exec_result
  def await(%{ref: ref, pid: pid}, timeout) do
    monitor_ref = pop_monitor_ref(ref, pid)

    case TaskHelper.await_result(
           %{pid: pid, ref: ref, monitor_ref: monitor_ref},
           :action_async_result,
           timeout,
           shutdown_grace_ms: 0,
           down_grace_ms: 0,
           normal_exit_result_grace_ms: 50,
           max_flush_messages: 1000,
           flush_timeout_ms: 0
         ) do
      {:ok, result} ->
        result

      {:error, :missing_result} ->
        {:error, Error.execution_error("Process completed but result was not received")}

      {:error, {:exit, reason}} ->
        {:error, Error.execution_error("Server error in async action: #{inspect(reason)}")}

      {:error, :timeout} ->
        {:error,
         Error.timeout_error("Async action timed out after #{timeout}ms", %{timeout: timeout})}
    end
  end

  @doc """
  Cancels a running asynchronous Action execution.

  ## Parameters

  - `async_ref`: The reference returned by `start/4`, or just the PID of the process to cancel.

  ## Returns

  - `:ok` if the cancellation was successful.
  - `{:error, reason}` if the cancellation failed or the input was invalid.
  """
  @spec cancel(async_ref() | pid()) :: :ok | exec_error
  def cancel(%{ref: ref, pid: pid}) do
    monitor_ref = pop_monitor_ref(ref, pid)

    _ =
      TaskHelper.await_result(
        %{pid: pid, ref: ref, monitor_ref: monitor_ref},
        :action_async_result,
        0,
        shutdown_grace_ms: 0,
        down_grace_ms: 0,
        normal_exit_result_grace_ms: 0,
        max_flush_messages: 1000,
        flush_timeout_ms: 0
      )

    :ok
  end

  def cancel(%{pid: pid}), do: cancel(pid)

  def cancel(pid) when is_pid(pid) do
    monitor_ref = pop_monitor_ref(pid)

    TaskHelper.timeout_cleanup(
      %{pid: pid, ref: make_ref(), monitor_ref: monitor_ref},
      :action_async_result,
      shutdown_grace_ms: 0,
      down_grace_ms: 0,
      max_flush_messages: 0,
      flush_timeout_ms: 0
    )

    :ok
  end

  def cancel(_), do: {:error, Error.validation_error("Invalid async ref for cancellation")}

  defp put_monitor_ref(ref, pid, monitor_ref) do
    Process.put(monitor_key(ref, pid), monitor_ref)
    Process.put(pid_monitor_key(pid), monitor_ref)
  end

  defp pop_monitor_ref(ref, pid) do
    monitor_ref = Process.get(monitor_key(ref, pid), :any)
    Process.delete(monitor_key(ref, pid))
    Process.delete(pid_monitor_key(pid))
    monitor_ref
  end

  defp pop_monitor_ref(pid) do
    monitor_ref = Process.get(pid_monitor_key(pid), :any)
    Process.delete(pid_monitor_key(pid))
    monitor_ref
  end

  defp monitor_key(ref, pid), do: {@monitor_key_prefix, ref, pid}
  defp pid_monitor_key(pid), do: {@pid_monitor_key_prefix, pid}
end
