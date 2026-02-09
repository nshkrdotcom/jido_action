defmodule Jido.Tools.LuaEval do
  @moduledoc """
  Execute a Lua code string in a sandboxed VM and return the values.

  ## Features

  - **Safe by default:** Uses tv-labs/lua's sandbox defaults to disable unsafe functions
  - **Timeout protection:** Configurable timeout with task isolation
  - **Global injection:** Pass Elixir values into the Lua environment
  - **Flexible returns:** Return all values or just the first one

  ## Security

  By default, the following unsafe Lua libraries are disabled:
  - `os` (getenv, execute, exit, etc.)
  - `io` and `file`
  - `package`, `require`, `dofile`
  - `load`, `loadfile`, `loadstring`

  Safe libraries remain enabled:
  - `string`, `math`, `table`
  - Basic Lua operations

  Set `enable_unsafe_libs: true` to disable sandboxing (use with caution).

  ## Examples

      # Simple arithmetic
      iex> Jido.Tools.LuaEval.run(%{code: "return 2 + 2"}, %{})
      {:ok, %{results: [4]}}

      # With globals
      iex> Jido.Tools.LuaEval.run(%{
        code: "return x + 5",
        globals: %{"x" => 10}
      }, %{})
      {:ok, %{results: [15]}}

      # Return first value only
      iex> Jido.Tools.LuaEval.run(%{
        code: "return 1, 2, 3",
        return_mode: :first
      }, %{})
      {:ok, %{result: 1}}

      # Timeout protection
      iex> Jido.Tools.LuaEval.run(%{
        code: "while true do end",
        timeout_ms: 50
      }, %{})
      {:error, %{type: :timeout, timeout_ms: 50}}
  """

  alias Jido.Exec.TaskHelper

  use Jido.Action,
    name: "lua_eval",
    description: "Execute a Lua code string in a sandboxed VM and return the values.",
    category: "scripting",
    vsn: "0.1.0",
    schema: [
      code: [
        type: :string,
        required: true,
        doc: "Lua code to execute (typically ends with `return ...` to produce values)."
      ],
      globals: [
        type: :map,
        default: %{},
        doc: "Map of global variables to inject into Lua state. Keys can be atoms or strings."
      ],
      return_mode: [
        type: {:in, [:list, :first]},
        default: :list,
        doc:
          "Shape of output: :list returns all values under `results`, :first returns only the first under `result`."
      ],
      enable_unsafe_libs: [
        type: :boolean,
        default: false,
        doc: "Enable unsafe libs (os/package/require/etc.) by disabling sandboxing."
      ],
      timeout_ms: [
        type: :non_neg_integer,
        default: 1000,
        doc: "Execution timeout in milliseconds."
      ],
      max_heap_bytes: [
        type: :non_neg_integer,
        default: 0,
        doc: "Per-process heap limit in bytes (0 = disabled)."
      ]
    ],
    output_schema: []

  @impl true
  def run(params, _context) do
    if Code.ensure_loaded?(Lua) do
      execute_lua(params)
    else
      msg =
        "Lua library (:lua) is not available. Add {:lua, \"~> 0.3\"} to your deps and run mix deps.get"

      return_error(:dependency_error, msg)
    end
  end

  defp execute_lua(params) do
    timeout_ms = Map.get(params, :timeout_ms, 1000)

    case TaskHelper.spawn_monitored(
           Jido.Action.TaskSupervisor,
           fn -> do_run(params) end,
           :lua_eval_result
         ) do
      {:ok, task_ref} ->
        await_lua_result(task_ref, timeout_ms)

      {:error, reason} ->
        return_error(:lua_error, "Failed to start Lua task: #{inspect(reason)}")
    end
  end

  defp await_lua_result(task_ref, timeout_ms) do
    case TaskHelper.await_result(
           task_ref,
           :lua_eval_result,
           timeout_ms,
           shutdown_grace_ms: 0,
           down_grace_ms: 0,
           normal_exit_result_grace_ms: 50,
           max_flush_messages: 1000,
           flush_timeout_ms: 0
         ) do
      {:ok, res} ->
        res

      {:error, {:exit, reason}} ->
        return_error(:lua_error, "Lua task exited: #{inspect(reason)}")

      {:error, :missing_result} ->
        return_error(:lua_error, "Lua task completed but result was not received")

      {:error, :timeout} ->
        {:error, %{type: :timeout, timeout_ms: timeout_ms}}
    end
  end

  defp do_run(params) do
    code = Map.fetch!(params, :code)
    globals = Map.get(params, :globals, %{})
    return_mode = Map.get(params, :return_mode, :list)
    enable_unsafe_libs = Map.get(params, :enable_unsafe_libs, false)
    max_heap_bytes = Map.get(params, :max_heap_bytes, 0)

    if is_integer(max_heap_bytes) and max_heap_bytes > 0 do
      :erlang.process_flag(:max_heap_size, %{size: max_heap_bytes, kill: true})
    end

    lua =
      if enable_unsafe_libs do
        # Explicitly disable sandboxing to allow unsafe libs
        Lua.new(sandboxed: [])
      else
        # Defaults sandbox unsafe functions (os/package/require/load/io/file/etc.)
        Lua.new()
      end

    lua =
      Enum.reduce(globals || %{}, lua, fn {k, v}, acc ->
        {encoded, acc2} = Lua.encode!(acc, v)
        path = if is_list(k), do: k, else: [k]
        Lua.set!(acc2, path, encoded)
      end)

    try do
      {values, _state} = Lua.eval!(lua, code)

      result =
        case return_mode do
          :first -> %{result: List.first(values)}
          _ -> %{results: values}
        end

      {:ok, result}
    rescue
      e in Lua.CompilerException ->
        return_error(:compile_error, Exception.message(e))

      e in Lua.RuntimeException ->
        return_error(:lua_error, Exception.message(e))

      e ->
        return_error(:lua_error, Exception.message(e))
    end
  end

  defp return_error(type, message) do
    {:error, %{type: type, message: message}}
  end
end
