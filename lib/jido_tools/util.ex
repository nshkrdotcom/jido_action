defmodule Jido.Tools.Util do
  @moduledoc false

  alias Jido.Action.Util

  @type key :: atom() | String.t()
  @type path :: [key()]

  @spec get_from(map(), map(), [key()], [path()], any()) :: any()
  def get_from(params, context, param_keys, context_paths, default \\ nil)
      when is_map(params) and is_map(context) and is_list(param_keys) and is_list(context_paths) do
    Util.first_present(
      [
        get_from_map(params, param_keys),
        get_from_paths(context, context_paths)
      ],
      default
    )
  end

  defp get_from_map(map, keys) do
    Enum.find_value(keys, fn key -> Map.get(map, key) end)
  end

  defp get_from_paths(map, paths) do
    Enum.find_value(paths, fn
      path when is_list(path) -> get_in(map, path)
      _invalid -> nil
    end)
  end
end
