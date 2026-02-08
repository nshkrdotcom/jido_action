defmodule Jido.Exec.TaskHelper do
  @moduledoc false

  alias Jido.Action.Error
  alias Jido.Exec.AsyncRef
  alias Jido.Exec.Supervisors

  @default_down_grace_period_ms 10
  @default_flush_timeout_ms 0
  @default_max_flush_messages 10

  @type monitored_task_ref :: AsyncRef.t()

  @type timeout_cleanup_opts :: [
          {:down_grace_period_ms, non_neg_integer()}
          | {:flush_timeout_ms, non_neg_integer()}
          | {:max_flush_messages, pos_integer()}
        ]

  @spec spawn_monitored(keyword(), atom(), (-> any())) ::
          {:ok, monitored_task_ref()} | {:error, Exception.t()}
  def spawn_monitored(opts, result_tag, task_fn) when is_list(opts) and is_atom(result_tag) do
    current_gl = Process.group_leader()
    parent = self()
    ref = make_ref()
    task_sup = Supervisors.task_supervisor(opts)

    case start_child(task_sup, opts, fn ->
           Process.group_leader(self(), current_gl)
           result = task_fn.()
           send(parent, {result_tag, ref, result})
         end) do
      {:ok, pid} ->
        {:ok, AsyncRef.new(ref, pid, Process.monitor(pid), parent)}

      {:error, error} ->
        {:error, error}
    end
  end

  @spec timeout_cleanup(module(), pid(), reference(), atom(), reference(), timeout_cleanup_opts()) ::
          :ok
  def timeout_cleanup(task_sup, pid, monitor_ref, result_tag, ref, opts \\ [])
      when is_atom(task_sup) and is_pid(pid) and is_reference(monitor_ref) and is_atom(result_tag) and
             is_reference(ref) and is_list(opts) do
    down_grace_period_ms = Keyword.get(opts, :down_grace_period_ms, @default_down_grace_period_ms)
    flush_timeout_ms = Keyword.get(opts, :flush_timeout_ms, @default_flush_timeout_ms)
    max_flush_messages = Keyword.get(opts, :max_flush_messages, @default_max_flush_messages)

    _ = Task.Supervisor.terminate_child(task_sup, pid)

    receive do
      {:DOWN, ^monitor_ref, :process, ^pid, _reason} -> :ok
    after
      down_grace_period_ms -> :ok
    end

    demonitor_flush(monitor_ref)

    flush_result_and_down_messages(
      result_tag,
      ref,
      pid,
      monitor_ref,
      max_flush_messages,
      flush_timeout_ms
    )
  end

  @spec demonitor_flush(reference()) :: :ok
  def demonitor_flush(monitor_ref) when is_reference(monitor_ref) do
    Process.demonitor(monitor_ref, [:flush])
    :ok
  end

  defp start_child(task_sup, opts, fun) do
    Task.Supervisor.start_child(task_sup, fun)
  catch
    :exit, {:noproc, _} ->
      {:error, missing_supervisor_error(task_sup, Keyword.get(opts, :jido))}

    :exit, reason ->
      {:error,
       Error.execution_error("Failed to start supervised task", %{
         reason: reason,
         task_supervisor: task_sup
       })}
  end

  defp missing_supervisor_error(task_sup, nil) do
    ArgumentError.exception(
      "Task supervisor #{inspect(task_sup)} is not running. " <>
        "Ensure `{Task.Supervisor, name: #{inspect(task_sup)}}` is started in your supervision tree."
    )
  end

  defp missing_supervisor_error(task_sup, jido) when is_atom(jido) do
    ArgumentError.exception(
      "Instance task supervisor #{inspect(task_sup)} is not running. " <>
        "Ensure the supervisor is started before using jido: #{inspect(jido)}. " <>
        "Add `{Task.Supervisor, name: #{inspect(task_sup)}}` to your supervision tree."
    )
  end

  defp flush_result_and_down_messages(
         _result_tag,
         _ref,
         _pid,
         _monitor_ref,
         0,
         _flush_timeout_ms
       ),
       do: :ok

  defp flush_result_and_down_messages(
         result_tag,
         ref,
         pid,
         monitor_ref,
         remaining,
         flush_timeout_ms
       ) do
    receive do
      {^result_tag, ^ref, _result} ->
        flush_result_and_down_messages(
          result_tag,
          ref,
          pid,
          monitor_ref,
          remaining - 1,
          flush_timeout_ms
        )

      {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
        flush_result_and_down_messages(
          result_tag,
          ref,
          pid,
          monitor_ref,
          remaining - 1,
          flush_timeout_ms
        )
    after
      flush_timeout_ms -> :ok
    end
  end
end
