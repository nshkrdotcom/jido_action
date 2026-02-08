defmodule Jido.Action.Utils do
  @moduledoc false

  @spec struct_to_map(any()) :: any()
  def struct_to_map(value) when is_struct(value), do: Map.from_struct(value)
  def struct_to_map(value), do: value
end
