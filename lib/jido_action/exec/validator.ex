defmodule Jido.Exec.Validator do
  @moduledoc """
  Provides validation functions for Jido.Exec module.

  This module contains validation logic for actions, parameters, and outputs
  that has been extracted from the main Exec module for better separation of concerns.
  """

  alias Jido.Action.Error

  @doc """
  Validates that the given action module is valid and can be executed.

  Checks that the module can be compiled and has the required run/2 function.
  """
  @spec validate_action(module()) :: :ok | {:error, Exception.t()}
  def validate_action(action) do
    case Code.ensure_compiled(action) do
      {:module, _} ->
        if function_exported?(action, :run, 2) do
          :ok
        else
          {:error,
           Error.validation_error(
             "Module #{inspect(action)} is not a valid action: missing run/2 function"
           )}
        end

      {:error, reason} ->
        {:error,
         Error.validation_error("Failed to compile module #{inspect(action)}: #{inspect(reason)}")}
    end
  end

  @doc """
  Validates parameters for the given action using the action's validate_params/1 function.

  Returns validated parameters on success or an error if validation fails.
  """
  @spec validate_params(module(), map()) :: {:ok, map()} | {:error, Exception.t()}
  def validate_params(action, params) do
    if function_exported?(action, :validate_params, 1) do
      case action.validate_params(params) do
        {:ok, params} ->
          {:ok, params}

        {:error, reason} ->
          {:error, reason}

        _ ->
          {:error, Error.validation_error("Invalid return from action.validate_params/1")}
      end
    else
      {:error,
       Error.validation_error(
         "Module #{inspect(action)} is not a valid action: missing validate_params/1 function"
       )}
    end
  end

  @doc """
  Validates output from an action using the action's validate_output/1 function if present.

  If the action doesn't have a validate_output/1 function, validation is skipped.
  """
  @spec validate_output(module(), map(), keyword()) :: {:ok, map()} | {:error, Exception.t()}
  def validate_output(action, output, opts) do
    log_level = Keyword.get(opts, :log_level, :info)

    if function_exported?(action, :validate_output, 1) do
      case action.validate_output(output) do
        {:ok, validated_output} ->
          maybe_log(log_level, :debug, fn ->
            "Output validation succeeded for #{inspect(action)}"
          end)

          {:ok, validated_output}

        {:error, reason} ->
          maybe_log(
            log_level,
            :debug,
            fn -> "Output validation failed for #{inspect(action)}: #{inspect(reason)}" end
          )

          {:error, reason}

        _ ->
          maybe_log(log_level, :debug, fn ->
            "Invalid return from action.validate_output/1"
          end)

          {:error, Error.validation_error("Invalid return from action.validate_output/1")}
      end
    else
      # If action doesn't have validate_output/1, skip output validation
      maybe_log(
        log_level,
        :debug,
        fn -> "No output validation function found for #{inspect(action)}, skipping" end
      )

      {:ok, output}
    end
  end

  defp maybe_log(threshold_level, message_level, message, metadata \\ []) do
    valid_levels = Logger.levels()

    if threshold_level in valid_levels and message_level in valid_levels and
         Logger.compare_levels(threshold_level, message_level) in [:lt, :eq] do
      Logger.log(message_level, message, metadata)
    else
      :ok
    end
  end
end
