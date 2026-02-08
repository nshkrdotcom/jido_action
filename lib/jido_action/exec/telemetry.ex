defmodule Jido.Exec.Telemetry do
  @moduledoc """
  Centralized telemetry, logging, and debugging helpers for Jido.Exec.

  This module consolidates all telemetry event emission, logging functionality,
  and error message extraction used throughout the execution system.
  """

  import Jido.Action.Util, only: [cond_log: 3]

  require Logger

  @max_metadata_depth 4
  @max_metadata_items 25
  @max_binary_bytes 1_024
  @max_log_chars 2_000
  @truncated_marker "[TRUNCATED]"
  @redacted_value "[REDACTED]"

  @redacted_keys [
    "password",
    "passphrase",
    "secret",
    "token",
    "access_token",
    "refresh_token",
    "authorization",
    "cookie",
    "api_key",
    "apikey",
    "client_secret",
    "private_key"
  ]

  @doc """
  Emits telemetry start event for action execution.
  """
  @spec emit_start_event(module(), map(), map()) :: :ok
  def emit_start_event(action, params, context) do
    :telemetry.execute(
      [:jido, :action, :start],
      %{system_time: System.system_time()},
      %{
        action: action,
        params: sanitize_metadata(params),
        context: sanitize_metadata(context)
      }
    )
  end

  @doc """
  Emits telemetry end event for action execution.
  """
  @spec emit_end_event(module(), map(), map(), any()) :: :ok
  def emit_end_event(action, params, context, result) do
    measurements = %{
      system_time: System.system_time(),
      # Duration would need to be calculated by caller
      duration: 0
    }

    metadata = %{
      action: action,
      params: sanitize_metadata(params),
      context: sanitize_metadata(context),
      result: sanitize_metadata(result)
    }

    :telemetry.execute([:jido, :action, :stop], measurements, metadata)
  end

  @doc """
  Logs the start of action execution.
  """
  @spec log_execution_start(module(), map(), map()) :: :ok
  def log_execution_start(action, params, context) do
    Logger.notice(
      "Executing #{inspect(action)} with params: #{inspect_for_log(params)} and context: #{inspect_for_log(context)}"
    )
  end

  @doc """
  Logs the end of action execution.
  """
  @spec log_execution_end(module(), map(), map(), any()) :: :ok
  def log_execution_end(action, _params, _context, result) do
    case result do
      {:ok, result_data} ->
        Logger.debug(
          "Finished execution of #{inspect(action)}, result: #{inspect_for_log(result_data)}"
        )

      {:ok, result_data, directive} ->
        Logger.debug(
          "Finished execution of #{inspect(action)}, result: #{inspect_for_log(result_data)}, directive: #{inspect_for_log(directive)}"
        )

      {:error, error} ->
        Logger.error("Action #{inspect(action)} failed: #{inspect_for_log(error)}")

      {:error, error, directive} ->
        Logger.error(
          "Action #{inspect(action)} failed: #{inspect_for_log(error)}, directive: #{inspect_for_log(directive)}"
        )

      other ->
        Logger.debug(
          "Finished execution of #{inspect(action)}, result: #{inspect_for_log(other)}"
        )
    end
  end

  @doc """
  Safely extracts error messages from various error types, handling nil and nested cases.
  """
  @spec extract_safe_error_message(any()) :: String.t()
  def extract_safe_error_message(error) do
    case error do
      %{message: %{message: inner_message}} when is_binary(inner_message) ->
        inner_message

      %{message: nil} ->
        ""

      %{message: message} when is_binary(message) ->
        message

      %{message: message} when is_struct(message) ->
        if Map.has_key?(message, :message) and is_binary(message.message) do
          message.message
        else
          inspect(message)
        end

      _ ->
        inspect(error)
    end
  end

  @doc """
  Conditional logging wrapper for start events.
  """
  @spec cond_log_start(atom(), module(), map(), map()) :: :ok
  def cond_log_start(log_level, action, params, context) do
    cond_log(
      log_level,
      :notice,
      "Executing #{inspect(action)} with params: #{inspect_for_log(params)} and context: #{inspect_for_log(context)}"
    )
  end

  @doc """
  Conditional logging wrapper for end events.
  """
  @spec cond_log_end(atom(), module(), any()) :: :ok
  def cond_log_end(log_level, action, result) do
    case result do
      {:ok, result_data} ->
        cond_log(
          log_level,
          :debug,
          "Finished execution of #{inspect(action)}, result: #{inspect_for_log(result_data)}"
        )

      {:ok, result_data, directive} ->
        cond_log(
          log_level,
          :debug,
          "Finished execution of #{inspect(action)}, result: #{inspect_for_log(result_data)}, directive: #{inspect_for_log(directive)}"
        )

      {:error, error} ->
        cond_log(log_level, :error, "Action #{inspect(action)} failed: #{inspect_for_log(error)}")

      {:error, error, directive} ->
        cond_log(
          log_level,
          :error,
          "Action #{inspect(action)} failed: #{inspect_for_log(error)}, directive: #{inspect_for_log(directive)}"
        )

      other ->
        cond_log(
          log_level,
          :debug,
          "Finished execution of #{inspect(action)}, result: #{inspect_for_log(other)}"
        )
    end
  end

  @doc """
  Conditional logging wrapper for errors.
  """
  @spec cond_log_error(atom(), module(), any()) :: :ok
  def cond_log_error(log_level, action, error) do
    cond_log(log_level, :error, "Action #{inspect(action)} failed: #{inspect_for_log(error)}")
  end

  @doc """
  Conditional logging wrapper for retry attempts.
  """
  @spec cond_log_retry(atom(), module(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          :ok
  def cond_log_retry(log_level, action, retry_count, max_retries, backoff) do
    cond_log(
      log_level,
      :info,
      "Retrying #{inspect(action)} (attempt #{retry_count + 1}/#{max_retries}) after #{backoff}ms backoff"
    )
  end

  @doc """
  Conditional logging wrapper for general messages.
  """
  @spec cond_log_message(atom(), atom(), String.t()) :: :ok
  def cond_log_message(log_level, level, message) do
    cond_log(log_level, level, message)
  end

  @doc """
  Conditional logging wrapper for function errors.
  """
  @spec cond_log_function_error(atom(), any()) :: :ok
  def cond_log_function_error(log_level, error) do
    cond_log(
      log_level,
      :warning,
      "Function invocation error in action: #{extract_safe_error_message(error)}"
    )
  end

  @doc """
  Conditional logging wrapper for unexpected errors.
  """
  @spec cond_log_unexpected_error(atom(), any()) :: :ok
  def cond_log_unexpected_error(log_level, error) do
    cond_log(
      log_level,
      :error,
      "Unexpected error in action: #{extract_safe_error_message(error)}"
    )
  end

  @doc """
  Conditional logging wrapper for caught errors.
  """
  @spec cond_log_caught_error(atom(), any()) :: :ok
  def cond_log_caught_error(log_level, reason) do
    cond_log(
      log_level,
      :warning,
      "Caught unexpected throw/exit in action: #{extract_safe_error_message(reason)}"
    )
  end

  @doc """
  Conditional logging wrapper for execution debug.
  """
  @spec cond_log_execution_debug(atom(), module(), map(), map()) :: :ok
  def cond_log_execution_debug(log_level, action, params, context) do
    cond_log(
      log_level,
      :debug,
      "Starting execution of #{inspect(action)}, params: #{inspect_for_log(params)}, context: #{inspect_for_log(context)}"
    )
  end

  @doc """
  Conditional logging wrapper for validation failures.
  """
  @spec cond_log_validation_failure(atom(), module(), any()) :: :ok
  def cond_log_validation_failure(log_level, action, validation_error) do
    cond_log(
      log_level,
      :error,
      "Action #{inspect(action)} output validation failed: #{inspect_for_log(validation_error)}"
    )
  end

  @doc """
  Conditional logging wrapper for general failures.
  """
  @spec cond_log_failure(atom(), String.t()) :: :ok
  def cond_log_failure(log_level, message) do
    cond_log(log_level, :debug, "Action Execution failed: #{message}")
  end

  defp inspect_for_log(value) do
    value
    |> sanitize_metadata()
    |> inspect(printable_limit: @max_log_chars, limit: @max_metadata_items)
    |> truncate_log()
  end

  defp truncate_log(message) when is_binary(message) and byte_size(message) > @max_log_chars do
    binary_part(message, 0, @max_log_chars) <> @truncated_marker
  end

  defp truncate_log(message), do: message

  defp sanitize_metadata(value, depth \\ 0)

  defp sanitize_metadata(_value, depth) when depth >= @max_metadata_depth, do: @truncated_marker

  defp sanitize_metadata(value, _depth)
       when is_binary(value) and byte_size(value) > @max_binary_bytes do
    binary_part(value, 0, @max_binary_bytes) <> @truncated_marker
  end

  defp sanitize_metadata(%_{} = struct, depth) do
    struct
    |> Map.from_struct()
    |> sanitize_metadata(depth)
  end

  defp sanitize_metadata(value, depth) when is_map(value) do
    value
    |> Enum.take(@max_metadata_items)
    |> Enum.map(fn {key, item} ->
      if sensitive_key?(key) do
        {key, @redacted_value}
      else
        {key, sanitize_metadata(item, depth + 1)}
      end
    end)
    |> Map.new()
    |> maybe_mark_truncated_map(value)
  end

  defp sanitize_metadata(value, depth) when is_list(value) do
    value
    |> Enum.take(@max_metadata_items)
    |> Enum.map(&sanitize_metadata(&1, depth + 1))
    |> maybe_mark_truncated_list(value)
  end

  defp sanitize_metadata(value, depth) when is_tuple(value) do
    original = Tuple.to_list(value)

    sanitized =
      original
      |> Enum.take(@max_metadata_items)
      |> Enum.map(&sanitize_metadata(&1, depth + 1))
      |> maybe_mark_truncated_tuple(value)

    List.to_tuple(sanitized)
  end

  defp sanitize_metadata(value, _depth), do: value

  defp maybe_mark_truncated_map(sanitized, original)
       when map_size(original) > @max_metadata_items do
    Map.put(sanitized, :__truncated__, true)
  end

  defp maybe_mark_truncated_map(sanitized, _original), do: sanitized

  defp maybe_mark_truncated_list(sanitized, original)
       when length(original) > @max_metadata_items do
    sanitized ++ [@truncated_marker]
  end

  defp maybe_mark_truncated_list(sanitized, _original), do: sanitized

  defp maybe_mark_truncated_tuple(sanitized, original)
       when tuple_size(original) > @max_metadata_items do
    sanitized ++ [@truncated_marker]
  end

  defp maybe_mark_truncated_tuple(sanitized, _original), do: sanitized

  defp sensitive_key?(key) when is_atom(key), do: sensitive_key?(Atom.to_string(key))

  defp sensitive_key?(key) when is_binary(key) do
    normalized = String.downcase(key)
    normalized in @redacted_keys
  end

  defp sensitive_key?(_key), do: false
end
