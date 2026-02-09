defmodule Jido.Exec.ConfigValidator do
  @moduledoc false

  require Logger

  @default_timeout 30_000
  @default_max_retries 1
  @default_backoff 250

  @spec validate_runtime_config() :: :ok
  def validate_runtime_config do
    validate_non_neg_integer(:default_timeout, @default_timeout)
    validate_non_neg_integer(:default_max_retries, @default_max_retries)
    validate_non_neg_integer(:default_backoff, @default_backoff)
    :ok
  end

  @spec validate_non_neg_integer(atom(), non_neg_integer()) :: :ok
  defp validate_non_neg_integer(key, fallback) do
    case Application.get_env(:jido_action, key, fallback) do
      value when is_integer(value) and value >= 0 ->
        :ok

      invalid ->
        Logger.warning(
          "Invalid :jido_action config for #{inspect(key)}: #{inspect(invalid)}. " <>
            "Expected a non-negative integer; using fallback #{fallback}."
        )
    end
  end
end
