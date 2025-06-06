defmodule Jido.InstructionTest do
  use JidoTest.Case, async: true
  alias Jido.Instruction
  alias Jido.Action.Error
  alias JidoTest.TestActions.BasicAction
  alias JidoTest.TestActions.NoSchema
  @moduletag :capture_log

  describe "normalize/3" do
    test "normalizes single instruction struct" do
      instruction = %Instruction{
        action: BasicAction,
        params: %{value: 1},
        context: %{local: true}
      }

      assert {:ok, [normalized]} = Instruction.normalize(instruction, %{request_id: "123"})
      assert normalized.action == BasicAction
      assert normalized.params == %{value: 1}
      assert normalized.context == %{local: true, request_id: "123"}
    end

    test "normalizes bare action module" do
      assert {:ok, [instruction]} = Instruction.normalize(BasicAction)
      assert instruction.action == BasicAction
      assert instruction.params == %{}
      assert instruction.context == %{}
    end

    test "normalizes action tuple with map params" do
      assert {:ok, [instruction]} = Instruction.normalize({BasicAction, %{value: 42}})
      assert instruction.action == BasicAction
      assert instruction.params == %{value: 42}
      assert instruction.context == %{}
    end

    test "normalizes action tuple with keyword list params" do
      assert {:ok, [instruction]} =
               Instruction.normalize({BasicAction, [value: 42, name: "test"]})

      assert instruction.action == BasicAction
      assert instruction.params == %{value: 42, name: "test"}
      assert instruction.context == %{}
    end

    test "returns error for invalid params list format" do
      assert {:error, %Error{}} =
               Instruction.normalize({BasicAction, ["not", "a", "keyword", "list"]})
    end

    test "normalizes list of mixed formats with different param types" do
      input = [
        BasicAction,
        {NoSchema, %{data: "test"}},
        {BasicAction, [value: 42]},
        %Instruction{action: BasicAction, context: %{local: true}}
      ]

      assert {:ok, [first, second, third, fourth]} =
               Instruction.normalize(input, %{request_id: "123"})

      assert first.action == BasicAction
      assert first.params == %{}
      assert first.context == %{request_id: "123"}

      assert second.action == NoSchema
      assert second.params == %{data: "test"}
      assert second.context == %{request_id: "123"}

      assert third.action == BasicAction
      assert third.params == %{value: 42}
      assert third.context == %{request_id: "123"}

      assert fourth.action == BasicAction
      assert fourth.params == %{}
      assert fourth.context == %{local: true, request_id: "123"}
    end

    test "returns error for invalid params format" do
      assert {:error, %Error{}} = Instruction.normalize({BasicAction, "invalid"})
    end

    test "returns error for invalid instruction format" do
      assert {:error, %Error{}} = Instruction.normalize(123)
    end

    test "merges options from input" do
      instruction = %Instruction{
        action: BasicAction,
        params: %{value: 1},
        opts: [timeout: 20_000]
      }

      assert {:ok, [normalized]} = Instruction.normalize(instruction, %{}, retry: true)
      assert normalized.opts == [timeout: 20_000, retry: true]
    end

    test "uses provided options when instruction has none" do
      assert {:ok, [normalized]} = Instruction.normalize(BasicAction, %{}, retry: true)
      assert normalized.opts == [retry: true]
    end
  end

  describe "normalize!/3" do
    test "returns normalized instructions directly" do
      instruction = %Instruction{
        action: BasicAction,
        params: %{value: 1},
        context: %{local: true}
      }

      [normalized] = Instruction.normalize!(instruction, %{request_id: "123"})
      assert normalized.action == BasicAction
      assert normalized.params == %{value: 1}
      assert normalized.context == %{local: true, request_id: "123"}
    end

    test "raises error for invalid input" do
      assert_raise ArgumentError, fn ->
        Instruction.normalize!(123)
      end
    end
  end

  describe "validate_allowed_actions/2" do
    test "returns ok when all actions are allowed" do
      instructions = [
        %Instruction{action: BasicAction},
        %Instruction{action: NoSchema}
      ]

      assert :ok = Instruction.validate_allowed_actions(instructions, [BasicAction, NoSchema])
    end

    test "returns error when actions are not allowed" do
      instructions = [
        %Instruction{action: BasicAction},
        %Instruction{action: NoSchema}
      ]

      assert {:error, %Error{}} =
               Instruction.validate_allowed_actions(instructions, [BasicAction])
    end

    test "validates single instruction" do
      instruction = %Instruction{action: BasicAction}
      assert :ok = Instruction.validate_allowed_actions(instruction, [BasicAction])
      assert {:error, %Error{}} = Instruction.validate_allowed_actions(instruction, [NoSchema])
    end
  end

  describe "normalize_single/3" do
    test "normalizes instruction struct" do
      instruction = %Instruction{
        action: BasicAction,
        params: %{value: 1},
        context: %{local: true}
      }

      assert {:ok, normalized} = Instruction.normalize_single(instruction, %{request_id: "123"})
      assert normalized.action == BasicAction
      assert normalized.params == %{value: 1}
      assert normalized.context == %{local: true, request_id: "123"}
    end

    test "normalizes bare action module" do
      assert {:ok, instruction} = Instruction.normalize_single(BasicAction)
      assert instruction.action == BasicAction
      assert instruction.params == %{}
      assert instruction.context == %{}
    end

    test "normalizes action tuple with map params" do
      assert {:ok, instruction} = Instruction.normalize_single({BasicAction, %{value: 42}})
      assert instruction.action == BasicAction
      assert instruction.params == %{value: 42}
      assert instruction.context == %{}
    end

    test "normalizes action tuple with keyword list params" do
      assert {:ok, instruction} =
               Instruction.normalize_single({BasicAction, [value: 42, name: "test"]})

      assert instruction.action == BasicAction
      assert instruction.params == %{value: 42, name: "test"}
      assert instruction.context == %{}
    end

    test "returns error for invalid params format" do
      assert {:error, %Error{}} =
               Instruction.normalize_single({BasicAction, "invalid"})
    end

    test "returns error for invalid instruction format" do
      assert {:error, %Error{}} = Instruction.normalize_single(123)
    end

    test "returns error for list input" do
      assert {:error, %Error{}} = Instruction.normalize_single([BasicAction])
    end

    test "merges options from input" do
      instruction = %Instruction{
        action: BasicAction,
        params: %{value: 1},
        opts: [timeout: 20_000]
      }

      assert {:ok, normalized} = Instruction.normalize_single(instruction, %{}, retry: true)
      assert normalized.opts == [timeout: 20_000, retry: true]
    end

    test "uses provided options when instruction has none" do
      assert {:ok, normalized} = Instruction.normalize_single(BasicAction, %{}, retry: true)
      assert normalized.opts == [retry: true]
    end
  end
end
