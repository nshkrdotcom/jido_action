defmodule Jido.Action.Config do
  @moduledoc false

  @default_exec_timeout 30_000
  @default_await_timeout 5_000
  @default_max_retries 1
  @default_backoff 250
  @default_max_backoff 30_000
  @default_compensation_timeout 5_000
  @default_async_down_grace_period_ms 100
  @default_async_shutdown_grace_period_ms 1_000
  @default_chain_down_grace_period_ms 100
  @default_chain_shutdown_grace_period_ms 1_000
  @default_compensation_down_grace_period_ms 100
  @default_exec_down_grace_period_ms 100
  @default_mailbox_flush_timeout_ms 0
  @default_mailbox_flush_max_messages :infinity

  @spec exec_timeout() :: non_neg_integer()
  def exec_timeout do
    Application.get_env(:jido_action, :default_timeout, @default_exec_timeout)
  end

  @spec await_timeout() :: non_neg_integer()
  def await_timeout do
    Application.get_env(
      :jido_action,
      :default_await_timeout,
      Application.get_env(:jido_action, :default_timeout, @default_await_timeout)
    )
  end

  @spec max_retries() :: non_neg_integer()
  def max_retries do
    Application.get_env(:jido_action, :default_max_retries, @default_max_retries)
  end

  @spec backoff() :: non_neg_integer()
  def backoff do
    Application.get_env(:jido_action, :default_backoff, @default_backoff)
  end

  @spec max_backoff() :: non_neg_integer()
  def max_backoff do
    Application.get_env(:jido_action, :default_max_backoff, @default_max_backoff)
  end

  @spec compensation_timeout() :: non_neg_integer()
  def compensation_timeout do
    Application.get_env(
      :jido_action,
      :default_compensation_timeout,
      @default_compensation_timeout
    )
  end

  @spec default_compensation_timeout() :: non_neg_integer()
  def default_compensation_timeout, do: @default_compensation_timeout

  @spec async_down_grace_period_ms() :: non_neg_integer()
  def async_down_grace_period_ms do
    Application.get_env(
      :jido_action,
      :async_down_grace_period_ms,
      @default_async_down_grace_period_ms
    )
  end

  @spec async_shutdown_grace_period_ms() :: non_neg_integer()
  def async_shutdown_grace_period_ms do
    Application.get_env(
      :jido_action,
      :async_shutdown_grace_period_ms,
      @default_async_shutdown_grace_period_ms
    )
  end

  @spec chain_down_grace_period_ms() :: non_neg_integer()
  def chain_down_grace_period_ms do
    Application.get_env(
      :jido_action,
      :chain_down_grace_period_ms,
      @default_chain_down_grace_period_ms
    )
  end

  @spec chain_shutdown_grace_period_ms() :: non_neg_integer()
  def chain_shutdown_grace_period_ms do
    Application.get_env(
      :jido_action,
      :chain_shutdown_grace_period_ms,
      @default_chain_shutdown_grace_period_ms
    )
  end

  @spec compensation_down_grace_period_ms() :: non_neg_integer()
  def compensation_down_grace_period_ms do
    Application.get_env(
      :jido_action,
      :compensation_down_grace_period_ms,
      @default_compensation_down_grace_period_ms
    )
  end

  @spec exec_down_grace_period_ms() :: non_neg_integer()
  def exec_down_grace_period_ms do
    Application.get_env(
      :jido_action,
      :exec_down_grace_period_ms,
      @default_exec_down_grace_period_ms
    )
  end

  @spec mailbox_flush_timeout_ms() :: non_neg_integer()
  def mailbox_flush_timeout_ms do
    Application.get_env(
      :jido_action,
      :mailbox_flush_timeout_ms,
      @default_mailbox_flush_timeout_ms
    )
  end

  @spec mailbox_flush_max_messages() :: non_neg_integer() | :infinity
  def mailbox_flush_max_messages do
    Application.get_env(
      :jido_action,
      :mailbox_flush_max_messages,
      @default_mailbox_flush_max_messages
    )
  end

  @spec validate!() :: :ok
  def validate! do
    validate_non_neg_integer!(:default_timeout, exec_timeout())
    validate_non_neg_integer!(:default_await_timeout, await_timeout())
    validate_non_neg_integer!(:default_max_retries, max_retries())
    validate_non_neg_integer!(:default_backoff, backoff())
    validate_non_neg_integer!(:default_max_backoff, max_backoff())
    validate_non_neg_integer!(:default_compensation_timeout, compensation_timeout())
    validate_non_neg_integer!(:async_down_grace_period_ms, async_down_grace_period_ms())
    validate_non_neg_integer!(:async_shutdown_grace_period_ms, async_shutdown_grace_period_ms())
    validate_non_neg_integer!(:chain_down_grace_period_ms, chain_down_grace_period_ms())
    validate_non_neg_integer!(:chain_shutdown_grace_period_ms, chain_shutdown_grace_period_ms())

    validate_non_neg_integer!(
      :compensation_down_grace_period_ms,
      compensation_down_grace_period_ms()
    )

    validate_non_neg_integer!(:exec_down_grace_period_ms, exec_down_grace_period_ms())
    validate_non_neg_integer!(:mailbox_flush_timeout_ms, mailbox_flush_timeout_ms())
    validate_flush_limit!(:mailbox_flush_max_messages, mailbox_flush_max_messages())

    :ok
  end

  defp validate_non_neg_integer!(_key, value) when is_integer(value) and value >= 0, do: :ok

  defp validate_non_neg_integer!(key, value) do
    raise ArgumentError,
          ":jido_action #{inspect(key)} must be a non-negative integer, got: #{inspect(value)}"
  end

  defp validate_flush_limit!(_key, :infinity), do: :ok
  defp validate_flush_limit!(key, value), do: validate_non_neg_integer!(key, value)
end
