defmodule Jido.Exec.TaskHelper do
  @moduledoc false

  alias Jido.Action.Config
  alias Jido.Action.Error
  alias Jido.Exec.AsyncRef
  alias Jido.Exec.Supervisors

  @type monitored_task_ref :: AsyncRef.t()
  @type flush_limit :: non_neg_integer() | :infinity
  @type task_supervisor_ref :: Supervisors.task_supervisor_ref()

  @type timeout_cleanup_opts :: [
          {:down_grace_period_ms, non_neg_integer()}
          | {:flush_timeout_ms, non_neg_integer()}
          | {:max_flush_messages, flush_limit()}
        ]

  @spec spawn_monitored(keyword(), atom(), (-> any())) ::
          {:ok, monitored_task_ref()} | {:error, Exception.t()}
  def spawn_monitored(opts, result_tag, task_fn) when is_list(opts) and is_atom(result_tag) do
    current_gl = Process.group_leader()
    parent = self()
    ref = make_ref()
    kill_on_owner_down = Keyword.get(opts, :kill_on_owner_down, true)

    with {:ok, task_sup} <- resolve_task_supervisor(opts),
         {:ok, pid} <-
           start_child(task_sup, opts, fn ->
             Process.group_leader(self(), current_gl)
             result = task_fn.()
             send(parent, {result_tag, ref, result})
           end) do
      maybe_spawn_owner_watchdog(parent, pid, kill_on_owner_down)
      {:ok, AsyncRef.new(ref, pid, Process.monitor(pid), parent, result_tag)}
    end
  end

  @spec timeout_cleanup(
          task_supervisor_ref(),
          pid(),
          reference(),
          atom(),
          reference(),
          timeout_cleanup_opts()
        ) :: :ok
  def timeout_cleanup(task_sup, pid, monitor_ref, result_tag, ref, opts \\ [])
      when (is_atom(task_sup) or is_pid(task_sup) or is_tuple(task_sup)) and
             is_pid(pid) and is_reference(monitor_ref) and is_atom(result_tag) and
             is_reference(ref) and is_list(opts) do
    down_grace_period_ms =
      Keyword.get(opts, :down_grace_period_ms, Config.async_down_grace_period_ms())

    _ = Task.Supervisor.terminate_child(task_sup, pid)

    receive do
      {:DOWN, ^monitor_ref, :process, ^pid, _reason} -> :ok
    after
      down_grace_period_ms -> :ok
    end

    demonitor_flush(monitor_ref)

    flush_messages(result_tag, ref, pid, monitor_ref, opts)
  end

  @spec demonitor_flush(reference()) :: :ok
  def demonitor_flush(monitor_ref) when is_reference(monitor_ref) do
    Process.demonitor(monitor_ref, [:flush])
    :ok
  end

  @spec flush_messages(atom(), reference(), pid(), reference() | nil, timeout_cleanup_opts()) ::
          :ok
  def flush_messages(result_tag, ref, pid, monitor_ref, opts \\ [])
      when is_atom(result_tag) and is_reference(ref) and is_pid(pid) and
             (is_reference(monitor_ref) or is_nil(monitor_ref)) and is_list(opts) do
    flush_timeout_ms = Keyword.get(opts, :flush_timeout_ms, Config.mailbox_flush_timeout_ms())

    max_flush_messages =
      Keyword.get(opts, :max_flush_messages, Config.mailbox_flush_max_messages())

    flush_result_and_down_messages(
      result_tag,
      ref,
      pid,
      monitor_ref,
      max_flush_messages,
      flush_timeout_ms
    )
  end

  defp resolve_task_supervisor(opts) do
    {:ok, Supervisors.task_supervisor(opts)}
  rescue
    e in ArgumentError -> {:error, e}
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

  @spec maybe_spawn_owner_watchdog(pid(), pid(), boolean()) :: :ok
  defp maybe_spawn_owner_watchdog(_owner, _task_pid, false), do: :ok

  defp maybe_spawn_owner_watchdog(owner, task_pid, true)
       when is_pid(owner) and is_pid(task_pid) do
    _watcher_pid = spawn_owner_watchdog(owner, task_pid)
    :ok
  end

  @spec spawn_owner_watchdog(pid(), pid()) :: pid()
  defp spawn_owner_watchdog(owner, task_pid) when is_pid(owner) and is_pid(task_pid) do
    spawn(fn ->
      owner_ref = Process.monitor(owner)
      task_ref = Process.monitor(task_pid)

      receive do
        {:DOWN, ^owner_ref, :process, ^owner, _reason} ->
          Process.exit(task_pid, :kill)
          drain_task_down(task_ref, task_pid)

        {:DOWN, ^task_ref, :process, ^task_pid, _reason} ->
          :ok
      end

      Process.demonitor(owner_ref, [:flush])
      Process.demonitor(task_ref, [:flush])
    end)
  end

  @spec drain_task_down(reference(), pid()) :: :ok
  defp drain_task_down(task_ref, task_pid) when is_reference(task_ref) and is_pid(task_pid) do
    receive do
      {:DOWN, ^task_ref, :process, ^task_pid, _reason} -> :ok
    after
      0 -> :ok
    end
  end

  defp flush_result_and_down_messages(
         result_tag,
         ref,
         pid,
         monitor_ref,
         :infinity,
         flush_timeout_ms
       ) do
    receive do
      {^result_tag, ^ref, _result} ->
        flush_result_and_down_messages(
          result_tag,
          ref,
          pid,
          monitor_ref,
          :infinity,
          flush_timeout_ms
        )

      {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
        flush_result_and_down_messages(
          result_tag,
          ref,
          pid,
          monitor_ref,
          :infinity,
          flush_timeout_ms
        )
    after
      flush_timeout_ms -> :ok
    end
  end

  defp flush_result_and_down_messages(
         result_tag,
         ref,
         _pid,
         nil,
         :infinity,
         flush_timeout_ms
       ) do
    receive do
      {^result_tag, ^ref, _result} ->
        flush_result_and_down_messages(
          result_tag,
          ref,
          nil,
          nil,
          :infinity,
          flush_timeout_ms
        )
    after
      flush_timeout_ms -> :ok
    end
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
         _pid,
         nil,
         remaining,
         flush_timeout_ms
       ) do
    receive do
      {^result_tag, ^ref, _result} ->
        flush_result_and_down_messages(
          result_tag,
          ref,
          nil,
          nil,
          remaining - 1,
          flush_timeout_ms
        )
    after
      flush_timeout_ms -> :ok
    end
  end

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
