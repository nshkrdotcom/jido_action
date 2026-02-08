defmodule Jido.Action.SchemaValidationTest do
  use ExUnit.Case, async: true

  alias Jido.Action
  alias Jido.Action.Error
  alias Jido.Action.Schema

  describe "validate/2 error normalization" do
    test "returns InvalidInputError for NimbleOptions schema failures" do
      schema = [count: [type: :integer, required: true]]

      assert {:error, %Error.InvalidInputError{} = error} =
               Schema.validate(schema, %{count: "not_an_integer"})

      assert is_binary(error.message)
    end

    test "returns InvalidInputError for Zoi schema failures" do
      schema =
        Zoi.object(%{
          count: Zoi.integer()
        })

      assert {:error, %Error.InvalidInputError{} = error} =
               Schema.validate(schema, %{count: "not_an_integer"})

      assert is_binary(error.message)
    end

    test "returns InvalidInputError for unsupported schema types" do
      assert {:error, %Error.InvalidInputError{message: "Unsupported schema type"}} =
               Schema.validate(:unsupported_schema, %{})
    end
  end

  describe "format_error/3 passthrough" do
    test "passes through existing exceptions unchanged" do
      existing_error = Error.validation_error("already normalized")

      assert existing_error == Schema.format_error(existing_error, "Action", __MODULE__)
    end
  end

  describe "runtime merge precedence semantics" do
    defmodule TrimmedNameAction do
      use Action,
        name: "trimmed_name_action",
        schema:
          Zoi.object(%{
            name: Zoi.string() |> Zoi.trim()
          })

      @impl true
      def run(params, _context), do: {:ok, params}
    end

    test "preserves unknown fields while using validated known-field values" do
      assert {:ok, %{name: "Alice", passthrough: true}} =
               TrimmedNameAction.validate_params(%{name: "  Alice  ", passthrough: true})
    end
  end
end
