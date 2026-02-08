defmodule JidoTest.Tools.LuaEvalCoverageTest do
  @moduledoc """
  Additional coverage tests for Jido.Tools.LuaEval.
  """
  use ExUnit.Case, async: true

  alias Jido.Tools.LuaEval

  @context %{}

  @moduletag :capture_log

  describe "enable_unsafe_libs option" do
    test "allows os functions when unsafe libs enabled" do
      params = %{code: "return type(os)", enable_unsafe_libs: true}
      assert {:ok, %{results: ["table"]}} = LuaEval.run(params, @context)
    end
  end

  describe "max_heap_bytes option" do
    test "runs normally with heap limit set" do
      params = %{code: "return 42", max_heap_bytes: 10_000_000}
      assert {:ok, %{results: [42]}} = LuaEval.run(params, @context)
    end

    test "runs with zero (disabled) heap limit" do
      params = %{code: "return 42", max_heap_bytes: 0}
      assert {:ok, %{results: [42]}} = LuaEval.run(params, @context)
    end
  end

  describe "globals with list keys" do
    test "injects globals with list-path keys" do
      params = %{
        code: "return greeting",
        globals: %{["greeting"] => "hello"}
      }

      assert {:ok, %{results: ["hello"]}} = LuaEval.run(params, @context)
    end
  end

  describe "nil globals" do
    test "handles nil globals map gracefully" do
      params = %{code: "return 1", globals: nil}
      assert {:ok, %{results: [1]}} = LuaEval.run(params, @context)
    end
  end

  describe "Lua.CompilerException vs Lua.RuntimeException" do
    test "returns error for compile errors" do
      params = %{code: "return +++"}

      assert {:error, %Jido.Action.Error.ExecutionFailureError{}} =
               LuaEval.run(params, @context)
    end

    test "returns error for runtime errors" do
      params = %{code: "error('runtime boom')"}

      assert {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} =
               LuaEval.run(params, @context)

      assert message =~ "boom"
    end
  end
end
