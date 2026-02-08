defmodule JidoTest.ExecResultPathsTest do
  @moduledoc """
  Tests for uncovered exec.ex result handling paths:
  - {:ok, result, directive} three-element ok tuple
  - {:error, reason, directive} three-element error tuple
  - unexpected return shape
  - ensure_error_struct with non-string/non-exception
  - ArgumentError exception path
  """
  use JidoTest.ActionCase, async: true

  @moduletag :capture_log

  defmodule DirectiveAction do
    @moduledoc false
    alias Jido.Action.Error

    use Jido.Action,
      name: "directive_action",
      schema: [
        mode: [type: :atom, required: true]
      ]

    @dialyzer {:nowarn_function, run: 2}
    @impl true
    def run(%{mode: :ok_with_directive}, _context) do
      {:ok, %{result: "done"}, :my_directive}
    end

    def run(%{mode: :error_with_directive}, _context) do
      {:error, Error.execution_error("fail"), :err_directive}
    end

    def run(%{mode: :unexpected}, _context) do
      :completely_wrong
    end

    def run(%{mode: :error_atom_reason}, _context) do
      {:error, {:some, :complex, :reason}}
    end
  end

  defmodule ArgErrorAction do
    @moduledoc false
    use Jido.Action,
      name: "arg_error_action",
      schema: []

    @impl true
    def run(_params, _context) do
      raise ArgumentError, message: "bad argument passed"
    end
  end

  describe "exec result with {:ok, result, directive}" do
    test "passes through three-element ok tuple" do
      assert {:ok, %{result: "done"}, :my_directive} =
               Jido.Exec.run(DirectiveAction, %{mode: :ok_with_directive})
    end
  end

  describe "exec result with {:error, reason, directive}" do
    test "passes through three-element error tuple" do
      assert {:error, %Jido.Action.Error.ExecutionFailureError{}, :err_directive} =
               Jido.Exec.run(DirectiveAction, %{mode: :error_with_directive})
    end
  end

  describe "exec result with unexpected return shape" do
    test "wraps unexpected result in execution error" do
      assert {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} =
               Jido.Exec.run(DirectiveAction, %{mode: :unexpected})

      assert message =~ "Unexpected return shape"
    end
  end

  describe "exec result with non-string non-exception error" do
    test "wraps complex error reason in execution error" do
      assert {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} =
               Jido.Exec.run(DirectiveAction, %{mode: :error_atom_reason})

      assert message =~ "Action failed"
    end
  end

  describe "exec ArgumentError handling" do
    test "wraps ArgumentError with proper message" do
      assert {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} =
               Jido.Exec.run(ArgErrorAction, %{})

      assert message =~ "Argument error"
    end
  end
end
