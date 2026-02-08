defmodule JidoTest.UtilCoverageTest do
  @moduledoc """
  Coverage tests for Jido.Action.Util uncovered normalize_result and wrap_error paths.
  """
  use ExUnit.Case, async: true

  alias Jido.Action.Util

  describe "normalize_result/1 nested tuples" do
    test "flattens {:error, {:ok, _value}}" do
      assert {:error, "Invalid nested error tuple"} =
               Util.normalize_result({:error, {:ok, "val"}})
    end

    test "flattens {:error, {:error, reason}}" do
      assert {:error, "nested failure"} =
               Util.normalize_result({:error, {:error, "nested failure"}})
    end

    test "flattens {:ok, {:ok, value}}" do
      assert {:ok, "inner"} = Util.normalize_result({:ok, {:ok, "inner"}})
    end

    test "flattens {:ok, {:error, reason}}" do
      assert {:error, "bad"} = Util.normalize_result({:ok, {:error, "bad"}})
    end

    test "passes through plain {:ok, value}" do
      assert {:ok, 42} = Util.normalize_result({:ok, 42})
    end

    test "passes through plain {:error, reason}" do
      assert {:error, :reason} = Util.normalize_result({:error, :reason})
    end

    test "wraps bare value" do
      assert {:ok, "bare"} = Util.normalize_result("bare")
    end
  end

  describe "wrap_ok/1" do
    test "passes through {:ok, _}" do
      assert {:ok, 1} = Util.wrap_ok({:ok, 1})
    end

    test "passes through {:error, _}" do
      assert {:error, :x} = Util.wrap_ok({:error, :x})
    end

    test "wraps bare value" do
      assert {:ok, "val"} = Util.wrap_ok("val")
    end
  end

  describe "wrap_error/1" do
    test "passes through {:error, _}" do
      assert {:error, :reason} = Util.wrap_error({:error, :reason})
    end

    test "wraps bare reason" do
      assert {:error, "reason"} = Util.wrap_error("reason")
    end
  end

  describe "validate_vsn/1" do
    test "accepts valid semver" do
      assert :ok = Util.validate_vsn("1.0.0")
      assert :ok = Util.validate_vsn("0.1.0-alpha")
    end

    test "rejects invalid semver" do
      assert {:error, _} = Util.validate_vsn("not.valid")
    end

    test "rejects non-string" do
      assert {:error, "Version must be a string."} = Util.validate_vsn(123)
    end
  end
end
