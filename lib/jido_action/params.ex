defmodule Jido.Action.Params do
  @moduledoc false

  alias Jido.Action.Error

  @type normalize_result :: {:ok, map()} | {:error, Exception.t()}

  @spec normalize_exec_params(any()) :: normalize_result()
  def normalize_exec_params(%_{} = error) when is_exception(error), do: {:error, error}
  def normalize_exec_params(params) when is_map(params), do: {:ok, params}
  def normalize_exec_params(params) when is_list(params), do: {:ok, Map.new(params)}
  def normalize_exec_params({:ok, params}) when is_map(params), do: {:ok, params}
  def normalize_exec_params({:ok, params}) when is_list(params), do: {:ok, Map.new(params)}

  def normalize_exec_params({:error, reason}),
    do: {:error, Error.validation_error(normalize_message(reason))}

  def normalize_exec_params(params) do
    {:error, Error.validation_error("Invalid params type: #{inspect(params)}")}
  end

  @spec normalize_exec_context(any()) :: normalize_result()
  def normalize_exec_context(context) when is_map(context), do: {:ok, context}
  def normalize_exec_context(context) when is_list(context), do: {:ok, Map.new(context)}

  def normalize_exec_context(context) do
    {:error, Error.validation_error("Invalid context type: #{inspect(context)}")}
  end

  @spec normalize_instruction_params(any()) :: normalize_result()
  def normalize_instruction_params(nil), do: {:ok, %{}}
  def normalize_instruction_params(params) when is_map(params), do: {:ok, params}

  def normalize_instruction_params(params) when is_list(params) do
    if Keyword.keyword?(params) do
      {:ok, Map.new(params)}
    else
      invalid_instruction_params(params)
    end
  end

  def normalize_instruction_params(invalid), do: invalid_instruction_params(invalid)

  @spec nil_to_default(any(), any()) :: any()
  def nil_to_default(nil, default), do: default
  def nil_to_default(value, _default), do: value

  defp invalid_instruction_params(params) do
    {:error,
     Error.execution_error(
       "Invalid params format. Params must be a map or keyword list.",
       %{
         params: params,
         expected_format: "%{key: value} or [key: value]"
       }
     )}
  end

  defp normalize_message(message) when is_binary(message), do: message
  defp normalize_message(message), do: inspect(message)
end
