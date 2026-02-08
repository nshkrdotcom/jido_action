defmodule Jido.Exec.TaskLifecycle do
  @moduledoc false
  import Kernel, except: [spawn: 3]

  alias Jido.Action.Config
  alias Jido.Exec.AsyncLifecycle
  alias Jido.Exec.AsyncRef
  alias Jido.Exec.TaskHelper

  @result_wrapper_tag :__jido_task_lifecycle_result__

  @type flush_limit :: non_neg_integer() | :infinity
  @type timeout_ms :: timeout()

  @type lifecycle_opts :: [
          {:spawn_opts, keyword()}
          | {:result_tag, atom()}
          | {:down_grace_period_ms, non_neg_integer()}
          | {:shutdown_grace_period_ms, non_neg_integer()}
          | {:flush_timeout_ms, non_neg_integer()}
          | {:max_flush_messages, flush_limit()}
          | {:no_result_error, (-> Exception.t())}
          | {:down_error, (term() -> Exception.t())}
          | {:timeout_error, (timeout_ms() -> Exception.t())}
        ]

  @spec run((-> any()), timeout_ms(), lifecycle_opts()) ::
          {:ok, any()} | {:error, Exception.t()}
  def run(task_fn, timeout, opts) when is_function(task_fn, 0) and is_list(opts) do
    spawn_opts = Keyword.get(opts, :spawn_opts, [])
    result_tag = Keyword.fetch!(opts, :result_tag)

    case spawn(spawn_opts, result_tag, fn -> {@result_wrapper_tag, task_fn.()} end) do
      {:ok, async_ref} ->
        case await(async_ref, timeout, opts) do
          {@result_wrapper_tag, result} ->
            {:ok, result}

          {:error, %_{} = error} when is_exception(error) ->
            {:error, error}

          unexpected ->
            {:error, Keyword.fetch!(opts, :down_error).({:unexpected_result, unexpected})}
        end

      {:error, %_{} = error} when is_exception(error) ->
        {:error, error}
    end
  end

  @spec spawn(keyword(), atom(), (-> any())) :: {:ok, AsyncRef.t()} | {:error, Exception.t()}
  def spawn(spawn_opts, result_tag, task_fn) when is_list(spawn_opts) and is_atom(result_tag) do
    TaskHelper.spawn_monitored(spawn_opts, result_tag, task_fn)
  end

  @spec await(AsyncRef.t(), timeout_ms(), lifecycle_opts()) :: any()
  def await(%AsyncRef{} = async_ref, timeout, opts) do
    AsyncLifecycle.await(
      async_ref,
      timeout,
      result_tag: Keyword.fetch!(opts, :result_tag),
      down_grace_period_ms: Keyword.fetch!(opts, :down_grace_period_ms),
      shutdown_grace_period_ms: Keyword.fetch!(opts, :shutdown_grace_period_ms),
      flush_timeout_ms: Keyword.get(opts, :flush_timeout_ms, Config.mailbox_flush_timeout_ms()),
      max_flush_messages:
        Keyword.get(opts, :max_flush_messages, Config.mailbox_flush_max_messages()),
      no_result_error: Keyword.fetch!(opts, :no_result_error),
      down_error: Keyword.fetch!(opts, :down_error),
      timeout_error: Keyword.fetch!(opts, :timeout_error)
    )
  end

  @spec cancel(AsyncRef.t(), keyword()) :: :ok
  def cancel(%AsyncRef{} = async_ref, opts \\ []) do
    shutdown_grace_period_ms =
      Keyword.get(opts, :shutdown_grace_period_ms, Config.async_shutdown_grace_period_ms())

    down_grace_period_ms =
      Keyword.get(opts, :down_grace_period_ms, Config.async_down_grace_period_ms())

    flush? = Keyword.get(opts, :flush?, true)
    flush_timeout_ms = Keyword.get(opts, :flush_timeout_ms, Config.mailbox_flush_timeout_ms())

    max_flush_messages =
      Keyword.get(opts, :max_flush_messages, Config.mailbox_flush_max_messages())

    AsyncLifecycle.shutdown_process(
      async_ref.pid,
      async_ref.monitor_ref,
      shutdown_grace_period_ms,
      down_grace_period_ms
    )

    if flush? and is_atom(async_ref.result_tag) do
      AsyncLifecycle.flush_messages(
        async_ref.ref,
        async_ref.pid,
        async_ref.monitor_ref,
        result_tag: async_ref.result_tag,
        flush_timeout_ms: flush_timeout_ms,
        max_flush_messages: max_flush_messages
      )
    end

    :ok
  end
end
