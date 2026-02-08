defmodule Jido.Action.Runtime do
  @moduledoc false

  alias Jido.Action.Error
  alias Jido.Action.Schema
  alias Jido.Action.Utils

  @spec validate_params(map(), module()) :: {:ok, map()} | {:error, any()}
  def validate_params(params, module) do
    with {:ok, params} <-
           normalize_hook_result(module.on_before_validate_params(params), module, :params),
         {:ok, validated_params} <- do_validate_params(params, module) do
      normalize_hook_result(module.on_after_validate_params(validated_params), module, :params)
    end
  end

  @spec validate_output(map(), module()) :: {:ok, map()} | {:error, any()}
  def validate_output(output, module) do
    with {:ok, output} <-
           normalize_hook_result(module.on_before_validate_output(output), module, :output),
         {:ok, validated_output} <- do_validate_output(output, module) do
      normalize_hook_result(module.on_after_validate_output(validated_output), module, :output)
    end
  end

  defp do_validate_params(params, module) do
    validate_against_schema(params, module.schema(), "Action", module)
  end

  defp do_validate_output(output, module) do
    validate_against_schema(output, module.output_schema(), "Action output", module)
  end

  defp validate_against_schema(data, schema, error_context, module) do
    known_keys = Schema.known_keys(schema)
    {known_data, unknown_data} = Map.split(data, known_keys)

    schema
    |> Schema.validate(known_data)
    |> handle_validation_result(unknown_data, error_context, module)
  end

  defp handle_validation_result({:ok, validated}, unknown, _error_context, _module) do
    # Keep unknown fields while ensuring validated schema fields override them.
    validated_map = Utils.struct_to_map(validated)
    {:ok, Map.merge(unknown, validated_map)}
  end

  defp handle_validation_result({:error, error}, _unknown, error_context, module) do
    error
    |> Schema.format_error(error_context, module)
    |> then(&{:error, &1})
  end

  defp normalize_hook_result({:ok, value}, _module, _kind), do: {:ok, value}

  defp normalize_hook_result({:error, %_{} = error}, _module, _kind) when is_exception(error),
    do: {:error, error}

  defp normalize_hook_result({:error, reason}, _module, kind) do
    {:error, Error.validation_error("Invalid #{kind} hook error: #{inspect(reason)}")}
  end

  defp normalize_hook_result(other, module, kind) do
    {:error,
     Error.validation_error(
       "Invalid return from #{inspect(module)} #{kind} hook: #{inspect(other)}"
     )}
  end
end
