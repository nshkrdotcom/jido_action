defmodule Jido.Action.TimeoutBudget do
  @moduledoc false

  @exec_deadline_key :__jido_exec_deadline_ms__
  @exec_deadline_key_string "__jido_exec_deadline_ms__"
  @workflow_deadline_key :__jido_workflow_deadline_ms__
  @workflow_deadline_key_string "__jido_workflow_deadline_ms__"

  @spec exec_deadline_key() :: atom()
  def exec_deadline_key, do: @exec_deadline_key

  @spec workflow_deadline_key() :: atom()
  def workflow_deadline_key, do: @workflow_deadline_key

  @spec normalize_runtime_keys(map()) :: map()
  def normalize_runtime_keys(context) when is_map(context) do
    context
    |> maybe_copy_integer_deadline(@exec_deadline_key_string, @exec_deadline_key)
    |> maybe_copy_integer_deadline(@workflow_deadline_key_string, @workflow_deadline_key)
  end

  @spec exec_deadline_ms(map()) :: integer() | nil
  def exec_deadline_ms(context),
    do: deadline_ms(context, @exec_deadline_key, @exec_deadline_key_string)

  @spec workflow_deadline_ms(map()) :: integer() | nil
  def workflow_deadline_ms(context),
    do: deadline_ms(context, @workflow_deadline_key, @workflow_deadline_key_string)

  @spec put_exec_deadline(map(), timeout()) :: map()
  def put_exec_deadline(context, :infinity) when is_map(context),
    do: normalize_runtime_keys(context)

  def put_exec_deadline(context, timeout_ms)
      when is_map(context) and is_integer(timeout_ms) and timeout_ms > 0 do
    normalized_context = normalize_runtime_keys(context)
    deadline_ms = System.monotonic_time(:millisecond) + timeout_ms

    bounded_deadline_ms =
      case exec_deadline_ms(normalized_context) do
        existing when is_integer(existing) -> min(existing, deadline_ms)
        _ -> deadline_ms
      end

    Map.put(normalized_context, @exec_deadline_key, bounded_deadline_ms)
  end

  def put_exec_deadline(context, _timeout) when is_map(context),
    do: normalize_runtime_keys(context)

  @spec put_workflow_deadline(map(), integer()) :: map()
  def put_workflow_deadline(context, deadline_ms)
      when is_map(context) and is_integer(deadline_ms) do
    context
    |> normalize_runtime_keys()
    |> Map.put(@workflow_deadline_key, deadline_ms)
  end

  @spec timeout_to_deadline(any()) :: integer() | nil
  def timeout_to_deadline(timeout_ms) when is_integer(timeout_ms) and timeout_ms > 0 do
    System.monotonic_time(:millisecond) + timeout_ms
  end

  def timeout_to_deadline(_timeout), do: nil

  @spec remaining_timeout_ms(any()) :: non_neg_integer() | nil
  def remaining_timeout_ms(deadline_ms) when is_integer(deadline_ms) do
    max(deadline_ms - System.monotonic_time(:millisecond), 0)
  end

  def remaining_timeout_ms(_deadline), do: nil

  @spec cap_timeout_by_remaining(any(), non_neg_integer() | nil) :: any()
  def cap_timeout_by_remaining(timeout, nil), do: timeout
  def cap_timeout_by_remaining(_timeout, 0), do: 0
  def cap_timeout_by_remaining(:infinity, remaining_timeout_ms), do: remaining_timeout_ms

  def cap_timeout_by_remaining(timeout, remaining_timeout_ms)
      when is_integer(timeout) and is_integer(remaining_timeout_ms) do
    min(timeout, remaining_timeout_ms)
  end

  def cap_timeout_by_remaining(timeout, _remaining_timeout_ms), do: timeout

  @spec timeout_ms_from_context(any(), keyword()) :: non_neg_integer() | nil
  def timeout_ms_from_context(context, opts \\ [])

  def timeout_ms_from_context(context, opts) when is_map(context) and is_list(opts) do
    keys = Keyword.get(opts, :keys, [:timeout, "timeout"])

    [
      remaining_timeout_ms(exec_deadline_ms(context))
      | Enum.map(keys, &Map.get(context, &1))
    ]
    |> Enum.find(&valid_timeout?/1)
  end

  def timeout_ms_from_context(_context, _opts), do: nil

  @spec drop_runtime_deadline_keys(map()) :: map()
  def drop_runtime_deadline_keys(context) when is_map(context) do
    context
    |> Map.delete(@exec_deadline_key)
    |> Map.delete(@exec_deadline_key_string)
    |> Map.delete(@workflow_deadline_key)
    |> Map.delete(@workflow_deadline_key_string)
  end

  defp deadline_ms(context, atom_key, string_key) when is_map(context) do
    case Map.get(context, atom_key) do
      value when is_integer(value) ->
        value

      _ ->
        case Map.get(context, string_key) do
          value when is_integer(value) -> value
          _ -> nil
        end
    end
  end

  defp maybe_copy_integer_deadline(context, string_key, atom_key) do
    atom_value = Map.get(context, atom_key)

    if is_integer(atom_value) do
      context
    else
      case Map.get(context, string_key) do
        string_value when is_integer(string_value) -> Map.put(context, atom_key, string_value)
        _ -> context
      end
    end
  end

  defp valid_timeout?(value) when is_integer(value) and value >= 0, do: true
  defp valid_timeout?(_value), do: false
end
