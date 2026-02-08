defmodule Jido.Exec.Compensation do
  @moduledoc """
  Handles error compensation logic for Jido actions.

  This module provides functionality to execute compensation actions when
  an action fails, if the action implements the `on_error/4` callback and
  has compensation enabled in its metadata.
  """
  use Private

  alias Jido.Action.Config
  alias Jido.Action.Error
  alias Jido.Exec.Supervisors
  alias Jido.Exec.TaskHelper
  alias Jido.Exec.Telemetry
  alias Jido.Exec.Types

  require Logger

  @flush_timeout_ms 0

  @type action :: Types.action()
  @type params :: Types.params()
  @type context :: Types.context()
  @type run_opts :: Types.run_opts()
  @type exec_result :: Types.exec_result()

  @doc """
  Checks if compensation is enabled for the given action.

  Compensation is enabled if:
  1. The action's metadata includes compensation configuration with `enabled: true`
  2. The action exports the `on_error/4` function

  ## Parameters

  - `action`: The action module to check

  ## Returns

  - `true` if compensation is enabled and available
  - `false` otherwise
  """
  @spec enabled?(action()) :: boolean()
  def enabled?(action) do
    metadata = action.__action_metadata__()
    compensation_opts = metadata[:compensation] || []

    enabled =
      case compensation_opts do
        opts when is_list(opts) -> Keyword.get(opts, :enabled, false)
        %{enabled: enabled} -> enabled
        _ -> false
      end

    enabled && function_exported?(action, :on_error, 4)
  end

  @doc """
  Handles action errors by executing compensation if enabled.

  This is the main entry point for error handling with compensation.
  If compensation is enabled, it will execute the action's `on_error/4` callback
  within a timeout. If compensation is disabled, it returns the original error.

  ## Parameters

  - `action`: The action module that failed
  - `params`: The parameters that were passed to the action
  - `context`: The context that was passed to the action
  - `error_or_tuple`: The error from the failed action, either an Exception or {Exception, directive}
  - `opts`: Execution options including timeout

  ## Returns

  - `{:error, compensated_error}` or `{:error, compensated_error, directive}` if compensation was attempted
  - `{:error, original_error}` or `{:error, original_error, directive}` if compensation is disabled
  """
  @spec handle_error(
          action(),
          params(),
          context(),
          Exception.t() | {Exception.t(), any()},
          run_opts()
        ) :: exec_result
  def handle_error(action, params, context, error_or_tuple, opts) do
    Logger.debug("Handle Action Error in handle_error: #{inspect(opts)}")
    # Extract error and directive if present
    {error, directive} =
      case error_or_tuple do
        {error, directive} -> {error, directive}
        error -> {error, nil}
      end

    if enabled?(action) do
      execute_compensation(action, params, context, error, directive, opts)
    else
      wrap_error_with_directive(error, directive)
    end
  end

  # Private functions are exposed to the test suite
  private do
    @spec execute_compensation(action(), params(), context(), Exception.t(), any(), run_opts()) ::
            exec_result
    defp execute_compensation(action, params, context, error, directive, opts) do
      metadata = action.__action_metadata__()
      compensation_opts = metadata[:compensation] || []
      timeout = get_compensation_timeout(opts, compensation_opts)
      max_attempts = get_compensation_max_attempts(opts, compensation_opts)

      compensation_run_opts =
        opts
        |> Keyword.take([
          :timeout,
          :backoff,
          :telemetry,
          :jido,
          :compensation_timeout,
          :compensation_max_retries
        ])
        |> Keyword.put(:compensation_timeout, timeout)
        |> Keyword.put(:compensation_max_retries, max(max_attempts - 1, 0))

      result =
        execute_compensation_with_retries(
          action,
          params,
          context,
          error,
          opts,
          compensation_run_opts,
          timeout,
          max_attempts
        )

      handle_task_result(result, error, directive, timeout, max_attempts)
    end

    @type compensation_context :: %{
            action: action(),
            params: params(),
            context: context(),
            error: Exception.t(),
            opts: run_opts(),
            compensation_run_opts: run_opts(),
            timeout: non_neg_integer(),
            max_attempts: pos_integer()
          }

    @spec execute_compensation_with_retries(
            action(),
            params(),
            context(),
            Exception.t(),
            run_opts(),
            run_opts(),
            non_neg_integer(),
            pos_integer()
          ) :: {:ok, any()} | {:exit, any()} | :timeout
    defp execute_compensation_with_retries(
           action,
           params,
           context,
           error,
           opts,
           compensation_run_opts,
           timeout,
           max_attempts
         ) do
      execution_context = %{
        action: action,
        params: params,
        context: context,
        error: error,
        opts: opts,
        compensation_run_opts: compensation_run_opts,
        timeout: timeout,
        max_attempts: max_attempts
      }

      do_execute_compensation_with_retries(execution_context, 1)
    end

    @spec do_execute_compensation_with_retries(
            compensation_context(),
            pos_integer()
          ) :: {:ok, any()} | {:exit, any()} | :timeout
    defp do_execute_compensation_with_retries(
           %{max_attempts: max_attempts} = execution_context,
           attempt
         ) do
      case execute_compensation_once(execution_context) do
        :timeout when attempt < max_attempts ->
          Logger.debug("Compensation timed out, retrying attempt #{attempt + 1}/#{max_attempts}")
          do_execute_compensation_with_retries(execution_context, attempt + 1)

        {:exit, reason} when attempt < max_attempts ->
          Logger.debug(
            "Compensation exited (#{inspect(reason)}), retrying attempt #{attempt + 1}/#{max_attempts}"
          )

          do_execute_compensation_with_retries(execution_context, attempt + 1)

        result ->
          result
      end
    end

    @spec execute_compensation_once(compensation_context()) ::
            {:ok, any()} | {:exit, any()} | :timeout
    defp execute_compensation_once(%{
           action: action,
           params: params,
           context: context,
           error: error,
           opts: opts,
           compensation_run_opts: compensation_run_opts,
           timeout: timeout
         }) do
      case TaskHelper.spawn_monitored(opts, :compensation_result, fn ->
             action.on_error(params, error, context, compensation_run_opts)
           end) do
        {:ok, %{ref: ref, pid: pid, monitor_ref: monitor_ref}} ->
          receive do
            {:compensation_result, ^ref, result} ->
              TaskHelper.demonitor_flush(monitor_ref)
              {:ok, result}

            {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
              case reason do
                :normal ->
                  receive do
                    {:compensation_result, ^ref, result} ->
                      TaskHelper.demonitor_flush(monitor_ref)
                      {:ok, result}
                  after
                    Config.compensation_down_grace_period_ms() ->
                      TaskHelper.demonitor_flush(monitor_ref)
                      {:exit, reason}
                  end

                _ ->
                  TaskHelper.demonitor_flush(monitor_ref)
                  {:exit, reason}
              end
          after
            timeout ->
              task_sup = Supervisors.task_supervisor(opts)

              TaskHelper.timeout_cleanup(
                task_sup,
                pid,
                monitor_ref,
                :compensation_result,
                ref,
                down_grace_period_ms: Config.compensation_down_grace_period_ms(),
                flush_timeout_ms: @flush_timeout_ms
              )

              :timeout
          end

        {:error, spawn_error} ->
          {:exit, spawn_error}
      end
    end

    @spec get_compensation_timeout(run_opts(), keyword() | map()) :: non_neg_integer()
    defp get_compensation_timeout(opts, compensation_opts) do
      Keyword.get(opts, :compensation_timeout) ||
        extract_timeout_from_compensation_opts(compensation_opts) ||
        Keyword.get(opts, :timeout) ||
        Config.compensation_timeout()
    end

    @spec get_compensation_max_attempts(run_opts(), keyword() | map()) :: pos_integer()
    defp get_compensation_max_attempts(opts, compensation_opts) do
      retries =
        Keyword.get(opts, :compensation_max_retries) ||
          extract_max_retries_from_compensation_opts(compensation_opts) ||
          1

      retries
      |> normalize_retries()
      |> max(1)
    end

    @spec extract_timeout_from_compensation_opts(keyword() | map() | any()) ::
            non_neg_integer() | nil
    defp extract_timeout_from_compensation_opts(opts) when is_list(opts),
      do: Keyword.get(opts, :timeout)

    defp extract_timeout_from_compensation_opts(%{timeout: timeout}), do: timeout
    defp extract_timeout_from_compensation_opts(_), do: nil

    @spec extract_max_retries_from_compensation_opts(keyword() | map() | any()) ::
            non_neg_integer() | nil
    defp extract_max_retries_from_compensation_opts(opts) when is_list(opts),
      do: Keyword.get(opts, :max_retries)

    defp extract_max_retries_from_compensation_opts(%{max_retries: max_retries}),
      do: max_retries

    defp extract_max_retries_from_compensation_opts(_), do: nil

    defp normalize_retries(value) when is_integer(value) and value >= 0, do: value
    defp normalize_retries(_), do: 1

    @spec handle_task_result(
            {:ok, any()} | {:exit, any()} | :timeout,
            Exception.t(),
            any(),
            non_neg_integer(),
            pos_integer()
          ) :: exec_result
    defp handle_task_result({:ok, result}, error, directive, _timeout, _max_attempts) do
      handle_compensation_result(result, error, directive)
    end

    defp handle_task_result(:timeout, error, directive, timeout, max_attempts) do
      build_timeout_error(error, directive, timeout, max_attempts)
    end

    defp handle_task_result({:exit, reason}, error, directive, _timeout, max_attempts) do
      build_exit_error(error, directive, reason, max_attempts)
    end

    @spec build_timeout_error(Exception.t(), any(), non_neg_integer(), pos_integer()) ::
            exec_result
    defp build_timeout_error(error, directive, timeout, max_attempts) do
      compensation_error = Error.timeout_error("Compensation timed out after #{timeout}ms")

      error_result =
        Error.execution_error(
          "Compensation timed out after #{timeout}ms for: #{inspect(error)}",
          %{
            compensated: false,
            compensation_result: nil,
            compensation_error: compensation_error,
            compensation_attempts: max_attempts,
            original_error: error
          }
        )

      wrap_error_with_directive(error_result, directive)
    end

    @spec build_exit_error(Exception.t(), any(), any(), pos_integer()) :: exec_result
    defp build_exit_error(error, directive, reason, max_attempts) do
      error_message = Telemetry.extract_safe_error_message(error)
      compensation_error = Error.execution_error("Compensation exited: #{inspect(reason)}")

      error_result =
        Error.execution_error(
          "Compensation crashed for: #{error_message}",
          %{
            compensated: false,
            compensation_result: nil,
            compensation_error: compensation_error,
            compensation_attempts: max_attempts,
            exit_reason: reason,
            original_error: error
          }
        )

      wrap_error_with_directive(error_result, directive)
    end

    @spec handle_compensation_result(any(), Exception.t(), any()) :: exec_result
    defp handle_compensation_result(result, original_error, directive) do
      result
      |> build_compensation_error(original_error)
      |> wrap_error_with_directive(directive)
    end

    @spec build_compensation_error(any(), Exception.t()) :: Exception.t()
    defp build_compensation_error({:ok, comp_result}, original_error) when is_map(comp_result) do
      # Extract message from error struct properly using safe helper
      error_message = Telemetry.extract_safe_error_message(original_error)

      Error.execution_error(
        "Compensation completed for: #{error_message}",
        %{
          compensated: true,
          compensation_result: comp_result,
          compensation_error: nil,
          original_error: original_error
        }
      )
    end

    defp build_compensation_error({:ok, comp_result}, original_error) do
      Error.execution_error(
        "Invalid compensation result for: #{inspect(original_error)}",
        %{
          compensated: false,
          compensation_result: nil,
          compensation_error:
            Error.execution_error(
              "Invalid compensation result",
              %{result: comp_result}
            ),
          original_error: original_error
        }
      )
    end

    defp build_compensation_error({:error, comp_error}, original_error) do
      # Extract message from error struct properly using safe helper
      error_message = Telemetry.extract_safe_error_message(original_error)

      Error.execution_error(
        "Compensation failed for: #{error_message}",
        %{
          compensated: false,
          compensation_result: nil,
          compensation_error: ensure_error_struct(comp_error),
          original_error: original_error
        }
      )
    end

    defp build_compensation_error(_invalid_result, original_error) do
      Error.execution_error(
        "Invalid compensation result for: #{inspect(original_error)}",
        %{
          compensated: false,
          compensation_result: nil,
          compensation_error: Error.execution_error("Invalid compensation result"),
          original_error: original_error
        }
      )
    end

    @spec wrap_error_with_directive(Exception.t(), any()) :: exec_result
    defp wrap_error_with_directive(error, nil), do: {:error, error}
    defp wrap_error_with_directive(error, directive), do: {:error, error, directive}

    defp ensure_error_struct(%_{} = error) when is_exception(error), do: error
    defp ensure_error_struct(reason) when is_binary(reason), do: Error.execution_error(reason)

    defp ensure_error_struct(reason) do
      Error.execution_error("Compensation failed", %{reason: reason})
    end
  end
end
