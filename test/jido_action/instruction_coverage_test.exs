defmodule JidoTest.InstructionCoverageTest do
  @moduledoc """
  Additional coverage tests for Jido.Instruction to cover uncovered branches.
  """
  use ExUnit.Case, async: true

  alias Jido.Instruction
  alias JidoTest.TestActions.BasicAction

  @moduletag :capture_log

  describe "new/1 edge cases" do
    test "returns error for non-map, non-keyword input" do
      assert {:error, %Jido.Action.Error.InvalidInputError{}} = Instruction.new("bad input")
    end

    test "returns error for nil input" do
      assert {:error, %Jido.Action.Error.InvalidInputError{}} = Instruction.new(nil)
    end

    test "handles nil params, context, and opts" do
      assert {:ok, instruction} =
               Instruction.new(%{action: BasicAction, params: nil, context: nil, opts: nil})

      assert instruction.params == %{}
      assert instruction.context == %{}
      assert instruction.opts == []
    end
  end

  describe "new!/1 edge cases" do
    test "raises for non-exception error" do
      # new! should raise for non-map/non-keyword input
      assert_raise Jido.Action.Error.InvalidInputError, fn ->
        Instruction.new!("bad input")
      end
    end
  end

  describe "normalize_single/3 with 3-element tuple" do
    test "normalizes action tuple with params and context" do
      assert {:ok, instruction} =
               Instruction.normalize_single(
                 {BasicAction, %{value: 42}, %{tenant: "abc"}},
                 %{global: true}
               )

      assert instruction.action == BasicAction
      assert instruction.params == %{value: 42}
      assert instruction.context == %{tenant: "abc", global: true}
    end
  end

  describe "normalize_single/3 with 4-element tuple" do
    test "normalizes action tuple with params, context, and opts" do
      assert {:ok, instruction} =
               Instruction.normalize_single(
                 {BasicAction, %{value: 42}, %{tenant: "abc"}, [timeout: 5000]},
                 %{global: true},
                 retry: true
               )

      assert instruction.action == BasicAction
      assert instruction.params == %{value: 42}
      assert instruction.context == %{tenant: "abc", global: true}
      assert instruction.opts == [timeout: 5000, retry: true]
    end

    test "returns error for invalid params in 4-element tuple" do
      assert {:error, _} =
               Instruction.normalize_single(
                 {BasicAction, "invalid", %{}, []},
                 %{}
               )
    end
  end

  describe "normalize/3 with context=nil" do
    test "handles nil context in list normalization" do
      assert {:ok, [instruction]} = Instruction.normalize([BasicAction], nil)
      assert instruction.context == %{}
    end
  end

  describe "normalize!/3 edge cases" do
    test "raises on invalid instruction in list" do
      assert_raise Jido.Action.Error.ExecutionFailureError, fn ->
        Instruction.normalize!([BasicAction, 123])
      end
    end
  end

  describe "validate_action_module/1" do
    test "returns ok for valid atom" do
      assert :ok = Instruction.validate_action_module(BasicAction)
    end

    test "returns error for non-atom" do
      assert {:error, "must be an atom"} = Instruction.validate_action_module("not_atom")
    end

    test "returns error for nil" do
      assert {:error, "cannot be nil"} = Instruction.validate_action_module(nil)
    end
  end

  describe "normalize_single/3 error on invalid params in 3-element tuple" do
    test "returns error for invalid params" do
      assert {:error, _} =
               Instruction.normalize_single(
                 {BasicAction, "invalid_params", %{ctx: true}},
                 %{}
               )
    end
  end
end
