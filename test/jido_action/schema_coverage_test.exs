defmodule JidoTest.Action.SchemaCoverageTest do
  @moduledoc """
  Additional coverage tests for Jido.Action.Schema to cover uncovered branches.
  """
  use ExUnit.Case, async: true

  alias Jido.Action.Schema
  alias Jido.Action.Error

  @moduletag :capture_log

  describe "schema_type/1" do
    test "returns :empty for empty list" do
      assert Schema.schema_type([]) == :empty
    end

    test "returns :nimble for keyword list" do
      assert Schema.schema_type(count: [type: :integer]) == :nimble
    end

    test "returns :zoi for Zoi schema" do
      schema = Zoi.object(%{name: Zoi.string()})
      assert Schema.schema_type(schema) == :zoi
    end

    test "returns :unknown for unsupported types" do
      assert Schema.schema_type(:not_a_schema) == :unknown
      assert Schema.schema_type(42) == :unknown
      assert Schema.schema_type("string") == :unknown
    end
  end

  describe "validate/2" do
    test "passes through data for empty schema" do
      assert {:ok, %{anything: "goes"}} = Schema.validate([], %{anything: "goes"})
    end

    test "validates NimbleOptions schema with map input" do
      schema = [count: [type: :integer, required: true]]
      assert {:ok, result} = Schema.validate(schema, %{count: 5})
      assert result.count == 5
    end

    test "validates NimbleOptions schema with keyword list input" do
      schema = [count: [type: :integer, required: true]]
      assert {:ok, result} = Schema.validate(schema, count: 5)
      assert result.count == 5
    end

    test "returns error for NimbleOptions validation failure" do
      schema = [count: [type: :integer, required: true]]
      assert {:error, %Error.InvalidInputError{}} = Schema.validate(schema, %{})
    end

    test "validates Zoi schema" do
      schema = Zoi.object(%{name: Zoi.string()})
      assert {:ok, _result} = Schema.validate(schema, %{name: "test"})
    end

    test "returns error for Zoi validation failure" do
      schema = Zoi.object(%{name: Zoi.integer()})
      assert {:error, %Error.InvalidInputError{}} = Schema.validate(schema, %{name: "not_int"})
    end
  end

  describe "known_keys/1" do
    test "returns empty list for empty schema" do
      assert Schema.known_keys([]) == []
    end

    test "returns keys from NimbleOptions schema" do
      schema = [name: [type: :string], age: [type: :integer]]
      assert Schema.known_keys(schema) == [:name, :age]
    end

    test "returns keys from Zoi Map schema" do
      schema = Zoi.object(%{name: Zoi.string(), age: Zoi.integer()})
      keys = Schema.known_keys(schema)
      assert :name in keys
      assert :age in keys
    end

    test "returns empty list for unknown schema types" do
      assert Schema.known_keys(:not_a_schema) == []
    end
  end

  describe "to_json_schema/1" do
    test "Zoi schema produces JSON schema" do
      schema = Zoi.object(%{name: Zoi.string(), count: Zoi.integer()})
      result = Schema.to_json_schema(schema)
      assert is_map(result)
    end

    test "NimbleOptions with required fields" do
      schema = [
        name: [type: :string, required: true, doc: "User name"],
        age: [type: :integer, doc: "User age"]
      ]

      result = Schema.to_json_schema(schema)
      assert result["required"] == ["name"]
      assert result["properties"]["name"]["type"] == "string"
      assert result["properties"]["name"]["description"] == "User name"
      assert result["properties"]["age"]["type"] == "integer"
    end

    test "NimbleOptions with map type" do
      schema = [data: [type: :map]]
      result = Schema.to_json_schema(schema)
      assert result["properties"]["data"]["type"] == "object"
    end

    test "NimbleOptions with keyword_list type" do
      schema = [opts: [type: :keyword_list]]
      result = Schema.to_json_schema(schema)
      assert result["properties"]["opts"]["type"] == "object"
    end

    test "NimbleOptions with float type" do
      schema = [ratio: [type: :float]]
      result = Schema.to_json_schema(schema)
      assert result["properties"]["ratio"]["type"] == "number"
    end

    test "NimbleOptions with boolean type" do
      schema = [active: [type: :boolean]]
      result = Schema.to_json_schema(schema)
      assert result["properties"]["active"]["type"] == "boolean"
    end

    test "NimbleOptions with {map, _} type" do
      schema = [settings: [type: {:map, :string}]]
      result = Schema.to_json_schema(schema)
      assert result["properties"]["settings"]["type"] == "object"
    end

    test "NimbleOptions with unknown type falls back to string" do
      schema = [custom: [type: {:custom, SomeModule, :validate, []}]]
      result = Schema.to_json_schema(schema)
      assert result["properties"]["custom"]["type"] == "string"
    end

    test "NimbleOptions with float enum" do
      schema = [ratio: [type: {:in, [1.0, 2.0, 3.0]}]]
      result = Schema.to_json_schema(schema)
      assert result["properties"]["ratio"]["type"] == "number"
      assert result["properties"]["ratio"]["enum"] == [1.0, 2.0, 3.0]
    end

    test "NimbleOptions with mixed-type enum (no type)" do
      schema = [val: [type: {:in, [1, "two", :three]}]]
      result = Schema.to_json_schema(schema)
      assert result["properties"]["val"]["enum"] == [1, "two", :three]
      refute Map.has_key?(result["properties"]["val"], "type")
    end

    test "NimbleOptions with number enum (mixed int/float)" do
      schema = [val: [type: {:in, [1, 2.0]}]]
      result = Schema.to_json_schema(schema)
      assert result["properties"]["val"]["type"] == "number"
    end

    test "NimbleOptions with keys option adds enum" do
      schema = [status: [type: :string, keys: [:a, :b, :c]]]
      result = Schema.to_json_schema(schema)
      assert result["properties"]["status"]["enum"] == ["a", "b", "c"]
    end
  end

  describe "format_error/3" do
    test "formats NimbleOptions error" do
      nimble_error = %NimbleOptions.ValidationError{
        key: :count,
        message: "is required",
        keys_path: []
      }

      result = Schema.format_error(nimble_error, "Action params", __MODULE__)
      assert %Error.InvalidInputError{} = result
    end

    test "formats Zoi error" do
      zoi_error = %Zoi.Error{
        message: "must be a string",
        path: [:name],
        code: :invalid_type
      }

      result = Schema.format_error(zoi_error, "Action params", __MODULE__)
      assert %Error.InvalidInputError{} = result
    end

    test "formats error list of Zoi.Error structs" do
      errors = [
        %Zoi.Error{path: [:name], message: "is required", code: :required},
        %Zoi.Error{path: [:age], message: "must be integer", code: :invalid_type}
      ]

      result = Schema.format_error(errors, "Action params", __MODULE__)
      assert %Error.InvalidInputError{} = result
    end

    test "passes through existing exceptions" do
      existing = Error.validation_error("already formatted")
      assert existing == Schema.format_error(existing, "Action params", __MODULE__)
    end

    test "handles unknown error type" do
      result = Schema.format_error(:unexpected, "Action params", __MODULE__)
      assert %Error.InvalidInputError{} = result
      assert result.message =~ "Validation failed"
    end
  end

  describe "validate_config_schema/2" do
    test "accepts keyword list schemas" do
      assert :ok = Schema.validate_config_schema(name: [type: :string])
    end

    test "accepts empty list schemas" do
      assert :ok = Schema.validate_config_schema([])
    end

    test "accepts Zoi schemas" do
      schema = Zoi.object(%{name: Zoi.string()})
      assert :ok = Schema.validate_config_schema(schema)
    end

    test "rejects unsupported types" do
      assert {:error, message} = Schema.validate_config_schema(:not_a_schema)
      assert message =~ "must be NimbleOptions schema or Zoi schema"
    end

    test "rejects integer" do
      assert {:error, _} = Schema.validate_config_schema(42)
    end
  end

  describe "extract_zoi_keys for struct schemas" do
    test "extracts keys from Zoi struct schema with map fields" do
      schema =
        Zoi.struct(Jido.Instruction, %{
          action: Zoi.atom(),
          params: Zoi.map()
        })

      keys = Schema.known_keys(schema)
      assert :action in keys
      assert :params in keys
    end
  end
end
