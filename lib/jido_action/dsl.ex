defmodule Jido.Action.DSL do
  @moduledoc """
  Provides shorthand DSL macros for quickly defining Actions.

  This module offers a more concise syntax for creating simple Actions,
  reducing boilerplate while maintaining full functionality. It's particularly
  useful for creating many similar Actions or for rapid prototyping.

  ## Features

  - `defaction/3` - Defines a single Action with inline implementation
  - `defactions/3` - Bulk generation of Actions from metadata (future)
  - Automatic schema generation from parameter lists
  - Full integration with the modular Action system

  ## Usage

      defmodule Math do
        import Jido.Action.DSL

        defaction add, "Adds two numbers",
          params: [a: :integer, b: :integer] do
            {:ok, %{result: a + b}}
        end

        defaction multiply, "Multiplies two numbers",
          params: [a: :integer, b: :integer],
          output_schema: [result: [type: :integer, required: true]] do
            {:ok, %{result: a * b}}
        end
      end

      # This generates Math.Add and Math.Multiply modules
      Math.Add.run(%{a: 1, b: 2}, %{})
      #=> {:ok, %{result: 3}}

  """

  @doc """
  Defines a single Action with inline implementation.

  This macro creates a full Action module as a submodule of the current module,
  automatically generating schemas from parameter definitions and providing
  a concise syntax for simple Actions.

  ## Parameters

  - `name` - The name of the Action (atom), will be titleized for module name
  - `description` - Description string for the Action
  - `opts` - Keyword list of options including:
    - `:params` - List of parameter definitions in the form `[name: type]`
    - `:output_schema` - Optional output schema (defaults to open)
    - `:category` - Optional category string
    - `:tags` - Optional list of tag strings
    - `:vsn` - Optional version string
  - `do_block` - The implementation block with Action logic

  ## Parameter Definition Format

  Parameters can be defined in several ways:

      # Simple type
      params: [name: :string, age: :integer]

      # With options
      params: [
        name: [type: :string, required: true, doc: "User name"],
        age: [type: :integer, default: 18, doc: "User age"]
      ]

      # Mixed format
      params: [
        name: :string,  # simple
        age: [type: :integer, default: 18]  # with options
      ]

  ## Examples

      defmodule UserActions do
        import Jido.Action.DSL

        defaction create_user, "Creates a new user",
          params: [
            name: [type: :string, required: true, doc: "User name"],
            email: [type: :string, required: true, doc: "User email"],
            age: [type: :integer, default: 18, doc: "User age"]
          ],
          category: "user_management",
          tags: ["users", "creation"] do
            # Params are available directly as variables
            user = %{name: name, email: email, age: age, id: UUID.uuid4()}
            {:ok, %{user: user}}
        end

        defaction calculate_discount, "Calculates user discount",
          params: [amount: :float, user_tier: :string] do
            discount =
              case user_tier do
                "premium" -> amount * 0.1
                "gold" -> amount * 0.05
                _ -> 0
              end
            {:ok, %{discount: discount}}
        end
      end

      # Generated modules: UserActions.CreateUser, UserActions.CalculateDiscount
      UserActions.CreateUser.run(%{name: "Alice", email: "alice@example.com"}, %{})

  """
  defmacro defaction(name, description, opts \\ [], do: body) do
    name_string =
      case name do
        {name_atom, _, _} -> Atom.to_string(name_atom)
        name_atom when is_atom(name_atom) -> Atom.to_string(name_atom)
        name_str when is_binary(name_str) -> name_str
      end

    module_name = name_string |> Macro.camelize() |> String.to_atom()
    params = Keyword.get(opts, :params, [])

    # Build the schema from params
    schema = build_schema_from_params(params)

    # Extract other options
    action_opts =
      opts
      |> Keyword.put(:name, name_string)
      |> Keyword.put(:description, description)
      |> Keyword.put(:schema, schema)
      |> Keyword.delete(:params)

    # Extract parameter names for the function body
    param_names = extract_param_names(params)

    # Create parameter variable extractions
    param_extracts =
      Enum.map(param_names, fn name ->
        quote do
          unquote(Macro.var(name, nil)) = Map.get(params, unquote(name))
        end
      end)

    quote do
      defmodule unquote(module_name) do
        use Jido.Action, unquote(action_opts)

        @impl true
        def run(params, context) do
          # Extract parameters as variables
          unquote_splicing(param_extracts)

          # Suppress "unused variable" warnings for context if it's not used
          _ = context

          # Execute the user's code
          unquote(body)
        end
      end
    end
  end

  # Private helper functions

  defp build_schema_from_params(params) do
    Enum.map(params, fn
      {name, type} when is_atom(type) ->
        {name, [type: type, required: true]}

      {name, opts} when is_list(opts) ->
        # Ensure required defaults to true if not specified
        opts_with_required =
          if Keyword.has_key?(opts, :required) do
            opts
          else
            Keyword.put(opts, :required, true)
          end

        {name, opts_with_required}
    end)
  end

  defp extract_param_names(params) do
    Enum.map(params, fn
      {name, _type_or_opts} -> name
    end)
  end

  @doc """
  Bulk generates Actions from a collection or template.

  This macro is designed for generating many similar Actions at once,
  such as CRUD operations for resources or Actions from external API schemas.

  **Note:** This is a placeholder for future implementation as outlined in
  the refactor plan. Currently raises a compile-time error.

  ## Planned Usage

      defmodule CRUDActions do
        import Jido.Action.DSL

        # Generate CRUD actions for each resource
        defactions for resource in [User, Post, Comment], :crud do
          # Would generate Create, Read, Update, Delete actions for each
        end

        # Generate from Ash resources
        defactions for resource in AshApp.Resources, :crud do
          # Generates actions based on Ash resource schemas
        end
      end

  """
  defmacro defactions(_iterator, _template, _opts \\ []) do
    quote do
      raise CompileError,
        description: "defactions/3 is not yet implemented - planned for future release",
        file: __ENV__.file,
        line: __ENV__.line
    end
  end
end
