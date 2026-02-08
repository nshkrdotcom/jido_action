defmodule Jido.Exec.AsyncLifecycle do
  @moduledoc false

  alias Jido.Exec.AsyncRef
  alias Jido.Exec.TaskHelper

  @type flush_limit :: non_neg_integer() | :infinity
  @type timeout_ms :: timeout()

  @type await_opts :: [
          {:result_tag, atom()}
          | {:down_grace_period_ms, non_neg_integer()}
          | {:shutdown_grace_period_ms, non_neg_integer()}
          | {:no_result_error, (-> Exception.t())}
          | {:down_error, (term() -> Exception.t())}
          | {:timeout_error, (timeout_ms() -> Exception.t())}
          | {:flush_timeout_ms, non_neg_integer()}
          | {:max_flush_messages, flush_limit()}
        ]

  @spec await(AsyncRef.t(), timeout_ms(), await_opts()) :: any()
  def await(%AsyncRef{ref: ref, pid: pid} = async_ref, timeout, opts) do
    result_tag = result_tag(opts)
    down_grace_period_ms = down_grace_period_ms(opts)
    shutdown_grace_period_ms = shutdown_grace_period_ms(opts)
    no_result_error = no_result_error(opts)
    down_error = down_error(opts)
    timeout_error = timeout_error(opts)
    monitor_ref = monitor_ref_for_current_process(async_ref, pid)

    result =
      receive do
        {^result_tag, ^ref, result} ->
          TaskHelper.demonitor_flush(monitor_ref)
          result

        {:DOWN, ^monitor_ref, :process, ^pid, :normal} ->
          await_result_after_normal_down(
            result_tag,
            ref,
            monitor_ref,
            down_grace_period_ms,
            no_result_error
          )

        {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
          TaskHelper.demonitor_flush(monitor_ref)
          {:error, down_error.(reason)}
      after
        timeout ->
          shutdown_process(
            pid,
            monitor_ref,
            shutdown_grace_period_ms,
            down_grace_period_ms
          )

          flush_messages(ref, pid, monitor_ref, opts)
          {:error, timeout_error.(timeout)}
      end

    flush_messages(ref, pid, monitor_ref, opts)
    result
  end

  @spec shutdown_process(pid(), reference() | nil, non_neg_integer(), non_neg_integer()) :: :ok
  def shutdown_process(pid, stale_monitor_ref, shutdown_grace_period_ms, down_grace_period_ms)
      when is_pid(pid) and is_integer(shutdown_grace_period_ms) and shutdown_grace_period_ms >= 0 and
             is_integer(down_grace_period_ms) and down_grace_period_ms >= 0 do
    monitor_ref = Process.monitor(pid)
    Process.exit(pid, :shutdown)

    receive do
      {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
        :ok
    after
      shutdown_grace_period_ms ->
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^monitor_ref, :process, ^pid, _reason} -> :ok
        after
          down_grace_period_ms -> :ok
        end
    end

    TaskHelper.demonitor_flush(monitor_ref)

    if is_reference(stale_monitor_ref) and stale_monitor_ref != monitor_ref do
      TaskHelper.demonitor_flush(stale_monitor_ref)
    end

    :ok
  end

  @spec flush_messages(reference(), pid(), reference() | nil, await_opts()) :: :ok
  def flush_messages(ref, pid, monitor_ref, opts) do
    flush_timeout_ms = Keyword.get(opts, :flush_timeout_ms, 0)
    max_flush_messages = Keyword.get(opts, :max_flush_messages, :infinity)

    TaskHelper.flush_messages(result_tag(opts), ref, pid, monitor_ref,
      flush_timeout_ms: flush_timeout_ms,
      max_flush_messages: max_flush_messages
    )
  end

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

  defp await_result_after_normal_down(
         result_tag,
         ref,
         monitor_ref,
         down_grace_period_ms,
         no_result_error
       ) do
    case receive_result(result_tag, ref, down_grace_period_ms) do
      {:ok, result} ->
        TaskHelper.demonitor_flush(monitor_ref)
        result

      :timeout ->
        case receive_result(result_tag, ref, down_grace_period_ms) do
          {:ok, result} ->
            TaskHelper.demonitor_flush(monitor_ref)
            result

          :timeout ->
            TaskHelper.demonitor_flush(monitor_ref)
            {:error, no_result_error.()}
        end
    end
  end

  defp receive_result(result_tag, ref, timeout_ms)
       when is_atom(result_tag) and is_reference(ref) and is_integer(timeout_ms) and
              timeout_ms >= 0 do
    receive do
      {^result_tag, ^ref, result} -> {:ok, result}
    after
      timeout_ms -> :timeout
    end
  end

  defp result_tag(opts), do: Keyword.fetch!(opts, :result_tag)
  defp down_grace_period_ms(opts), do: Keyword.fetch!(opts, :down_grace_period_ms)
  defp shutdown_grace_period_ms(opts), do: Keyword.fetch!(opts, :shutdown_grace_period_ms)
  defp no_result_error(opts), do: Keyword.fetch!(opts, :no_result_error)
  defp down_error(opts), do: Keyword.fetch!(opts, :down_error)
  defp timeout_error(opts), do: Keyword.fetch!(opts, :timeout_error)
end
