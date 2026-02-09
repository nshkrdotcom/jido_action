defmodule Jido.Exec.TaskHelper do
  @moduledoc false

  @default_shutdown_grace_ms 100
  @default_down_grace_ms 0
  @default_normal_exit_result_grace_ms 50
  @default_max_flush_messages 1000
  @default_flush_timeout_ms 0

  @type monitor_ref_t :: reference() | :any

  @type task_ref :: %{
          pid: pid(),
          ref: reference(),
          monitor_ref: monitor_ref_t()
        }

  @type await_result :: {:ok, term()} | {:error, :timeout | :missing_result | {:exit, term()}}

  @spec spawn_monitored(module(), (-> term()), atom(), keyword()) ::
          {:ok, task_ref()} | {:error, term()}
  def spawn_monitored(task_supervisor, fun, result_tag, opts \\ [])
      when is_function(fun, 0) and is_atom(result_tag) and is_list(opts) do
    parent = self()
    ref = make_ref()

    caller_group_leader =
      if Keyword.get(opts, :preserve_group_leader, false), do: Process.group_leader(), else: nil

    case Task.Supervisor.start_child(task_supervisor, fn ->
           maybe_set_group_leader(caller_group_leader)

           result = fun.()
           send(parent, {result_tag, ref, result})
         end) do
      {:ok, pid} ->
        monitor_ref = Process.monitor(pid)
        {:ok, %{pid: pid, ref: ref, monitor_ref: monitor_ref}}

      {:error, _reason} = error ->
        error
    end
  end

  @spec await_result(task_ref(), atom(), timeout(), keyword()) :: await_result()
  def await_result(
        %{pid: pid, ref: ref, monitor_ref: monitor_ref} = task_ref,
        result_tag,
        timeout_ms,
        opts \\ []
      )
      when is_atom(result_tag) and is_list(opts) do
    receive do
      {^result_tag, ^ref, result} ->
        demonitor_flush(monitor_ref)
        {:ok, result}

      {:DOWN, down_ref, :process, ^pid, reason}
      when ((is_reference(monitor_ref) and down_ref == monitor_ref) or monitor_ref == :any) and
             reason in [:normal, :noproc] ->
        normal_exit_grace_ms =
          resolve_non_neg_integer(
            opts,
            :normal_exit_result_grace_ms,
            @default_normal_exit_result_grace_ms
          )

        result =
          receive do
            {^result_tag, ^ref, task_result} -> {:ok, task_result}
          after
            normal_exit_grace_ms -> {:error, :missing_result}
          end

        demonitor_flush(monitor_ref)

        case result do
          {:ok, _task_result} = ok ->
            ok

          {:error, :missing_result} = missing ->
            flush_related_messages(result_tag, ref, monitor_ref, pid, opts)
            missing
        end

      {:DOWN, down_ref, :process, ^pid, reason}
      when (is_reference(monitor_ref) and down_ref == monitor_ref) or monitor_ref == :any ->
        demonitor_flush(monitor_ref)
        flush_related_messages(result_tag, ref, monitor_ref, pid, opts)
        {:error, {:exit, reason}}
    after
      timeout_ms ->
        timeout_cleanup(task_ref, result_tag, opts)
        {:error, :timeout}
    end
  end

  @spec demonitor_flush(monitor_ref_t()) :: boolean() | :ok
  def demonitor_flush(:any), do: :ok

  def demonitor_flush(monitor_ref) when is_reference(monitor_ref) do
    Process.demonitor(monitor_ref, [:flush])
  end

  @spec timeout_cleanup(task_ref(), atom(), keyword()) :: :ok
  def timeout_cleanup(
        %{pid: pid, ref: ref, monitor_ref: monitor_ref},
        result_tag,
        opts \\ []
      )
      when is_atom(result_tag) and is_list(opts) do
    shutdown_grace_ms =
      resolve_non_neg_integer(opts, :shutdown_grace_ms, @default_shutdown_grace_ms)

    down_grace_ms = resolve_non_neg_integer(opts, :down_grace_ms, @default_down_grace_ms)

    Process.exit(pid, :shutdown)

    case wait_for_down(monitor_ref, pid, shutdown_grace_ms) do
      {:down, _reason} ->
        :ok

      :timeout ->
        if Process.alive?(pid), do: Process.exit(pid, :kill)
        _ = wait_for_down(monitor_ref, pid, down_grace_ms)
        :ok
    end

    demonitor_flush(monitor_ref)
    flush_related_messages(result_tag, ref, monitor_ref, pid, opts)
  end

  defp maybe_set_group_leader(nil), do: :ok

  defp maybe_set_group_leader(caller_group_leader) when is_pid(caller_group_leader) do
    Process.group_leader(self(), caller_group_leader)
  end

  @spec wait_for_down(monitor_ref_t(), pid(), timeout()) :: {:down, term()} | :timeout
  defp wait_for_down(monitor_ref, pid, timeout_ms) do
    receive do
      {:DOWN, down_ref, :process, ^pid, reason}
      when (is_reference(monitor_ref) and down_ref == monitor_ref) or monitor_ref == :any ->
        {:down, reason}
    after
      timeout_ms ->
        :timeout
    end
  end

  @spec flush_related_messages(atom(), reference(), monitor_ref_t(), pid(), keyword()) :: :ok
  defp flush_related_messages(result_tag, ref, monitor_ref, pid, opts) do
    max_flush_messages =
      resolve_non_neg_integer(opts, :max_flush_messages, @default_max_flush_messages)

    flush_timeout_ms = resolve_non_neg_integer(opts, :flush_timeout_ms, @default_flush_timeout_ms)
    deadline_ms = System.monotonic_time(:millisecond) + flush_timeout_ms

    do_flush_related_messages(
      result_tag,
      ref,
      monitor_ref,
      pid,
      max_flush_messages,
      deadline_ms,
      0
    )
  end

  @spec do_flush_related_messages(
          atom(),
          reference(),
          monitor_ref_t(),
          pid(),
          non_neg_integer(),
          integer(),
          non_neg_integer()
        ) :: :ok
  defp do_flush_related_messages(
         _result_tag,
         _ref,
         _monitor_ref,
         _pid,
         max_messages,
         _deadline_ms,
         count
       )
       when count >= max_messages do
    :ok
  end

  defp do_flush_related_messages(
         result_tag,
         ref,
         monitor_ref,
         pid,
         max_messages,
         deadline_ms,
         count
       ) do
    receive_timeout = max(deadline_ms - System.monotonic_time(:millisecond), 0)

    receive do
      {^result_tag, ^ref, _result} ->
        do_flush_related_messages(
          result_tag,
          ref,
          monitor_ref,
          pid,
          max_messages,
          deadline_ms,
          count + 1
        )

      {:DOWN, down_ref, :process, ^pid, _reason}
      when (is_reference(monitor_ref) and down_ref == monitor_ref) or monitor_ref == :any ->
        do_flush_related_messages(
          result_tag,
          ref,
          monitor_ref,
          pid,
          max_messages,
          deadline_ms,
          count + 1
        )
    after
      receive_timeout ->
        :ok
    end
  end

  @spec resolve_non_neg_integer(keyword(), atom(), non_neg_integer()) :: non_neg_integer()
  defp resolve_non_neg_integer(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value >= 0 -> value
      _ -> default
    end
  end
end
