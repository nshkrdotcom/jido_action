defmodule Jido.Exec.Async do
  @moduledoc """
  Handles asynchronous execution of Actions using Task.Supervisor.

  This module provides the core async implementation for Jido.Exec,
  managing task supervision, cleanup, and async lifecycle.
  """
  use Private

  alias Jido.Action.Config
  alias Jido.Action.Error
  alias Jido.Exec.AsyncLifecycle
  alias Jido.Exec.AsyncRef
  alias Jido.Exec.TaskHelper
  alias Jido.Exec.Types

  @result_tag :action_async_result

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

  - `%Jido.Exec.AsyncRef{}` on success.
  - `{:error, exception}` when the supervised task cannot be started.
  """
  @spec start(action(), params(), context(), run_opts()) :: async_ref() | {:error, Exception.t()}
  def start(action, params \\ %{}, context \\ %{}, opts \\ []) do
    case TaskHelper.spawn_monitored(opts, @result_tag, fn ->
           Jido.Exec.run(action, params, context, opts)
         end) do
      {:ok, async_ref} ->
        async_ref

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Same as `start/4`, but raises when the async task cannot be started.
  """
  @spec start!(action(), params(), context(), run_opts()) :: async_ref()
  def start!(action, params \\ %{}, context \\ %{}, opts \\ []) do
    case start(action, params, context, opts) do
      %AsyncRef{} = async_ref -> async_ref
      {:error, %_{} = error} when is_exception(error) -> raise error
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
  def await(%AsyncRef{} = async_ref, timeout),
    do:
      AsyncLifecycle.await(
        async_ref,
        timeout,
        result_tag: @result_tag,
        down_grace_period_ms: Config.async_down_grace_period_ms(),
        shutdown_grace_period_ms: Config.async_shutdown_grace_period_ms(),
        flush_timeout_ms: Config.mailbox_flush_timeout_ms(),
        max_flush_messages: Config.mailbox_flush_max_messages(),
        no_result_error: fn ->
          Error.execution_error("Process completed but result was not received")
        end,
        down_error: fn reason ->
          Error.execution_error("Server error in async action: #{inspect(reason)}")
        end,
        timeout_error: fn timeout_ms ->
          Error.timeout_error("Async action timed out after #{timeout_ms}ms", %{
            timeout: timeout_ms
          })
        end
      )

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
    AsyncLifecycle.shutdown_process(
      pid,
      monitor_ref,
      Config.async_shutdown_grace_period_ms(),
      Config.async_down_grace_period_ms()
    )

    :ok
  end

  def cancel(%{pid: pid} = legacy_async_ref)
      when is_pid(pid) and not is_struct(legacy_async_ref, AsyncRef) do
    legacy_async_ref
    |> AsyncRef.from_legacy_cancel_map(__MODULE__)
    |> cancel()
  end

  def cancel(pid) when is_pid(pid) do
    AsyncLifecycle.shutdown_process(
      pid,
      nil,
      Config.async_shutdown_grace_period_ms(),
      Config.async_down_grace_period_ms()
    )

    :ok
  end

  def cancel(_), do: {:error, Error.validation_error("Invalid async ref for cancellation")}
end
