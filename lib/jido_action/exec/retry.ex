defmodule Jido.Exec.Retry do
  @moduledoc """
  Retry logic and backoff calculations for action execution.

  This module centralizes retry behavior, including:
  - Exponential backoff calculations with capping
  - Retry decision logic based on error type and attempt count
  - Retry option processing and validation
  """

  alias Jido.Action.Config
  alias Jido.Action.Error
  alias Jido.Exec.Telemetry

  require Logger

  @doc """
  Calculate exponential backoff time for a retry attempt.

  Uses exponential backoff with a maximum cap of 30 seconds.

  ## Parameters

  - `retry_count`: The current retry attempt number (0-based)
  - `initial_backoff`: The initial backoff time in milliseconds

  ## Returns

  The calculated backoff time in milliseconds, capped at 30,000ms.

  ## Examples

      iex> Jido.Exec.Retry.calculate_backoff(0, 250)
      250
      
      iex> Jido.Exec.Retry.calculate_backoff(1, 250)
      500
      
      iex> Jido.Exec.Retry.calculate_backoff(2, 250)
      1000
  """
  @spec calculate_backoff(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def calculate_backoff(retry_count, initial_backoff) do
    (initial_backoff * :math.pow(2, retry_count))
    |> round()
    |> min(Config.max_backoff())
  end

  @doc """
  Determine if an action should be retried based on the error and attempt count.

  ## Parameters

  - `error`: The error that occurred during execution
  - `retry_count`: The current retry attempt number
  - `max_retries`: The maximum number of retries allowed
  - `opts`: Additional options (currently unused but reserved for future use)

  ## Returns

  `true` if the action should be retried, `false` otherwise.

  ## Examples

      iex> Jido.Exec.Retry.should_retry?({:error, "network error"}, 0, 3, [])
      true
      
      iex> Jido.Exec.Retry.should_retry?({:error, "network error"}, 3, 3, [])
      false
  """
  @spec should_retry?(any(), non_neg_integer(), non_neg_integer(), keyword()) :: boolean()
  def should_retry?(error, retry_count, max_retries, _opts) do
    retry_count < max_retries and retryable_error?(error)
  end

  defp retryable_error?(error) do
    case extract_exception(error) do
      %Error.InvalidInputError{} ->
        false

      %Error.ConfigurationError{} ->
        false

      %_{} = exception when is_exception(exception) ->
        case retry_hint(exception) do
          true -> true
          false -> false
          :unset -> true
        end

      _other ->
        true
    end
  end

  defp extract_exception({:error, reason, _other}), do: reason
  defp extract_exception({:error, reason}), do: reason
  defp extract_exception(%_{} = error) when is_exception(error), do: error
  defp extract_exception(other), do: other

  defp retry_hint(%{details: details}) do
    case extract_retry_value(details) do
      {:ok, true} -> true
      {:ok, false} -> false
      _ -> :unset
    end
  end

  defp retry_hint(_), do: :unset

  defp extract_retry_value(details) when is_map(details) do
    if Map.has_key?(details, :retry) do
      {:ok, Map.get(details, :retry)}
    else
      :error
    end
  end

  defp extract_retry_value(details) when is_list(details) do
    if Keyword.keyword?(details) and Keyword.has_key?(details, :retry) do
      {:ok, Keyword.get(details, :retry)}
    else
      :error
    end
  end

  defp extract_retry_value(_), do: :error

  @doc """
  Execute a retry with proper backoff and logging.

  This function handles the retry orchestration including:
  - Calculating the backoff time
  - Logging the retry attempt
  - Sleeping for the backoff period

  ## Parameters

  - `action`: The action module being retried
  - `retry_count`: The current retry attempt number
  - `max_retries`: The maximum number of retries allowed
  - `initial_backoff`: The initial backoff time in milliseconds
  - `opts`: Options for logging and other behavior
  - `retry_fn`: Function to call for the actual retry attempt

  ## Returns

  The result of calling `retry_fn`.
  """
  @spec execute_retry(
          module(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          keyword(),
          function()
        ) :: any()
  def execute_retry(action, retry_count, max_retries, initial_backoff, opts, retry_fn) do
    backoff = calculate_backoff(retry_count, initial_backoff)

    Telemetry.cond_log_retry(
      Keyword.get(opts, :log_level, :info),
      action,
      retry_count,
      max_retries,
      backoff
    )

    receive do
    after
      backoff -> :ok
    end

    retry_fn.()
  end

  @doc """
  Get default retry configuration values.

  ## Returns

  A keyword list with default retry configuration:
  - `:max_retries`: Default maximum retry attempts
  - `:backoff`: Default initial backoff time in milliseconds
  """
  @spec default_retry_config() :: keyword()
  def default_retry_config do
    [
      max_retries: Config.max_retries(),
      backoff: Config.backoff()
    ]
  end

  @doc """
  Extract and validate retry options from the provided opts.

  ## Parameters

  - `opts`: The options keyword list to extract retry config from

  ## Returns

  A keyword list with validated retry configuration values.
  """
  @spec extract_retry_opts(keyword()) :: keyword()
  def extract_retry_opts(opts) do
    defaults = default_retry_config()

    [
      max_retries: Keyword.get(opts, :max_retries, defaults[:max_retries]),
      backoff: Keyword.get(opts, :backoff, defaults[:backoff])
    ]
  end
end
