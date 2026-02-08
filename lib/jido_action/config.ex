defmodule Jido.Action.Config do
  @moduledoc false

  @default_exec_timeout 30_000
  @default_await_timeout 5_000
  @default_max_retries 1
  @default_backoff 250
  @default_max_backoff 30_000
  @default_compensation_timeout 5_000

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

  @spec validate!() :: :ok
  def validate! do
    validate_non_neg_integer!(:default_timeout, exec_timeout())
    validate_non_neg_integer!(:default_await_timeout, await_timeout())
    validate_non_neg_integer!(:default_max_retries, max_retries())
    validate_non_neg_integer!(:default_backoff, backoff())
    validate_non_neg_integer!(:default_max_backoff, max_backoff())
    validate_non_neg_integer!(:default_compensation_timeout, compensation_timeout())
    :ok
  end

  defp validate_non_neg_integer!(_key, value) when is_integer(value) and value >= 0, do: :ok

  defp validate_non_neg_integer!(key, value) do
    raise ArgumentError,
          ":jido_action #{inspect(key)} must be a non-negative integer, got: #{inspect(value)}"
  end
end
