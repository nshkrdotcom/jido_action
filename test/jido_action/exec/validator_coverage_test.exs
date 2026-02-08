defmodule JidoTest.Exec.ValidatorCoverageTest do
  @moduledoc """
  Additional coverage tests for Jido.Exec.Validator module.
  """
  use ExUnit.Case, async: true

  alias Jido.Exec.Validator

  @moduletag :capture_log

  describe "validate_action/1" do
    test "returns ok for valid action module" do
      assert :ok = Validator.validate_action(JidoTest.TestActions.BasicAction)
    end

    test "returns error for module without run/2" do
      assert {:error, %Jido.Action.Error.InvalidInputError{message: message}} =
               Validator.validate_action(Enum)

      assert message =~ "missing run/2 function"
    end

    test "returns error for non-existent module" do
      assert {:error, %Jido.Action.Error.InvalidInputError{message: message}} =
               Validator.validate_action(NonExistent.Module.That.DoesNot.Exist)

      assert message =~ "is not loaded"
    end
  end

  describe "validate_params/2" do
    test "validates params for valid action" do
      assert {:ok, validated} =
               Validator.validate_params(JidoTest.TestActions.BasicAction, %{value: 42})

      assert validated.value == 42
    end

    test "returns error for invalid params" do
      assert {:error, _} =
               Validator.validate_params(JidoTest.TestActions.BasicAction, %{value: "not_int"})
    end

    test "returns error for non-existent module" do
      assert {:error, %Jido.Action.Error.InvalidInputError{message: message}} =
               Validator.validate_params(NonExistent.Module.That.DoesNot.Exist, %{})

      assert message =~ "not loaded"
    end

    test "returns error for module without validate_params/1" do
      assert {:error, %Jido.Action.Error.InvalidInputError{message: message}} =
               Validator.validate_params(Enum, %{})

      assert message =~ "missing validate_params/1"
    end
  end

  describe "validate_output/3" do
    test "skips validation when action has no validate_output function" do
      assert {:ok, %{anything: "goes"}} =
               Validator.validate_output(
                 JidoTest.TestActions.NoSchema,
                 %{anything: "goes"},
                 []
               )
    end

    test "returns error for non-existent module" do
      assert {:error, %Jido.Action.Error.InvalidInputError{message: message}} =
               Validator.validate_output(
                 NonExistent.Module.That.DoesNot.Exist,
                 %{},
                 []
               )

      assert message =~ "not loaded"
    end

    test "validates output for action with output schema" do
      assert {:ok, _} =
               Validator.validate_output(
                 JidoTest.TestActions.OutputSchemaAction,
                 %{result: "HELLO", length: 5},
                 []
               )
    end

    test "returns error for invalid output" do
      assert {:error, _} =
               Validator.validate_output(
                 JidoTest.TestActions.OutputSchemaAction,
                 %{wrong_field: "value"},
                 []
               )
    end
  end
end
