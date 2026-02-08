defmodule JidoTest.RemainingCoverageTest do
  @moduledoc """
  Targeted coverage tests for remaining gaps across multiple modules.
  """
  use ExUnit.Case, async: true

  @moduletag :capture_log

  # ---- Jido.Action.Utils (50% -> 100%) ----
  describe "Jido.Action.Utils.struct_to_map/1" do
    test "converts struct to map" do
      uri = %URI{host: "example.com", path: "/test"}
      result = Jido.Action.Utils.struct_to_map(uri)
      assert is_map(result)
      refute Map.has_key?(result, :__struct__)
      assert result.host == "example.com"
    end

    test "passes through non-struct values" do
      assert Jido.Action.Utils.struct_to_map(%{a: 1}) == %{a: 1}
      assert Jido.Action.Utils.struct_to_map("hello") == "hello"
      assert Jido.Action.Utils.struct_to_map(42) == 42
    end
  end

  # ---- Jido.Action.Config (92.8% -> 100%) ----
  describe "Jido.Action.Config" do
    test "validate! passes with default config" do
      assert :ok = Jido.Action.Config.validate!()
    end

    test "compensation_timeout returns default value" do
      assert is_integer(Jido.Action.Config.compensation_timeout())
    end

    test "max_backoff returns default value" do
      assert is_integer(Jido.Action.Config.max_backoff())
    end
  end

  # ---- Jido.Action.Util edge cases (88.4% -> higher) ----
  describe "Jido.Action.Util" do
    test "cond_log with invalid levels doesn't log" do
      assert :ok = Jido.Action.Util.cond_log(:invalid_level, :info, "test")
      assert :ok = Jido.Action.Util.cond_log(:info, :invalid_level, "test")
    end

    test "cond_log when threshold is higher than message level" do
      assert :ok = Jido.Action.Util.cond_log(:error, :debug, "should not log")
    end

    test "convert_nested_opt with non-compensation keyword list" do
      assert {:other_key, [a: 1, b: 2]} =
               Jido.Action.Util.convert_nested_opt({:other_key, [a: 1, b: 2]})
    end

    test "convert_nested_opt with non-keyword list" do
      assert {:compensation, [1, 2, 3]} =
               Jido.Action.Util.convert_nested_opt({:compensation, [1, 2, 3]})
    end

    test "convert_nested_opt with non-tuple" do
      assert :atom = Jido.Action.Util.convert_nested_opt(:atom)
    end
  end

  # ---- Jido.Action.Runtime edge cases (89.4% -> higher) ----
  describe "Jido.Action.Runtime normalize_hook_result" do
    defmodule BadHookAction do
      use Jido.Action,
        name: "bad_hook_action",
        schema: []

      @impl true
      def on_before_validate_params(_params) do
        {:error, "plain string error from hook"}
      end

      @impl true
      def run(params, _context), do: {:ok, params}
    end

    defmodule WeirdHookAction do
      use Jido.Action,
        name: "weird_hook_action",
        schema: []

      @impl true
      def on_before_validate_params(_params) do
        :unexpected_return
      end

      @impl true
      def run(params, _context), do: {:ok, params}
    end

    test "handles non-exception error from hook" do
      assert {:error, %Jido.Action.Error.InvalidInputError{}} =
               Jido.Exec.run(BadHookAction, %{})
    end

    test "handles unexpected return from hook" do
      assert {:error, %Jido.Action.Error.InvalidInputError{}} =
               Jido.Exec.run(WeirdHookAction, %{})
    end
  end
end
