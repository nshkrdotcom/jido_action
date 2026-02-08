defmodule JidoTest.Exec.ChainCoverageTest do
  @moduledoc """
  Additional coverage tests for Jido.Exec.Chain module.
  Covers interrupt check, async cancel/timeout, and invalid action paths.
  """
  use JidoTest.ActionCase, async: false

  import ExUnit.CaptureLog

  alias Jido.Exec.Chain
  alias JidoTest.TestActions.Add
  alias JidoTest.TestActions.Multiply

  @moduletag :capture_log

  defmodule OkWithDirectiveAction do
    use Jido.Action, name: "ok_with_directive_action", schema: []

    @impl true
    def run(_params, _context), do: {:ok, %{merged: true}, :noop_directive}
  end

  defmodule ErrorWithDirectiveAction do
    alias Jido.Action.Error

    use Jido.Action, name: "error_with_directive_action", schema: []

    @impl true
    def run(_params, _context) do
      {:error, Error.execution_error("with directive"), :noop_directive}
    end
  end

  describe "chain/3 with interrupt check" do
    test "interrupts chain when interrupt_check returns true" do
      capture_log(fn ->
        result =
          Chain.chain(
            [Add, Multiply],
            %{value: 5, amount: 1},
            interrupt_check: fn -> true end
          )

        assert {:interrupted, %{value: 5}} = result
      end)
    end

    test "does not interrupt when interrupt_check returns false" do
      capture_log(fn ->
        result =
          Chain.chain(
            [Add, Multiply],
            %{value: 5, amount: 2},
            interrupt_check: fn -> false end
          )

        assert {:ok, %{value: 14}} = result
      end)
    end

    test "interrupts after first action succeeds" do
      count = :counters.new(1, [:atomics])

      capture_log(fn ->
        result =
          Chain.chain(
            [Add, Multiply],
            %{value: 5, amount: 1},
            interrupt_check: fn ->
              # Return false on first call (let Add run), true on second
              :counters.add(count, 1, 1)
              :counters.get(count, 1) > 1
            end
          )

        assert {:interrupted, %{value: 6}} = result
      end)
    end
  end

  describe "chain/3 with invalid action formats" do
    test "handles non-module/non-tuple action in chain" do
      capture_log(fn ->
        result = Chain.chain([Add, 42, Multiply], %{value: 5})
        assert {:error, %Jido.Action.Error.InvalidInputError{}} = result
      end)
    end

    test "handles nil action parameter in tuple" do
      capture_log(fn ->
        result = Chain.chain([{Add, nil}], %{value: 5})
        assert {:error, _} = result
      end)
    end
  end

  describe "chain async cancel" do
    test "cancels a running async chain" do
      capture_log(fn ->
        async_ref =
          Chain.chain(
            [Add, Multiply],
            %{value: 5, amount: 2},
            async: true
          )

        assert is_map(async_ref)
        assert :ok = Chain.cancel(async_ref)
      end)
    end

    test "cancels by pid" do
      capture_log(fn ->
        async_ref =
          Chain.chain(
            [Add, Multiply],
            %{value: 5, amount: 2},
            async: true
          )

        assert :ok = Chain.cancel(async_ref.pid)
      end)
    end

    test "returns error for invalid cancel argument" do
      assert {:error, _} = Chain.cancel("not_a_ref")
    end
  end

  describe "chain/3 with map action params" do
    test "validates map action params with string keys" do
      capture_log(fn ->
        result = Chain.chain([{Add, %{"amount" => 2}}], %{value: 5})
        assert {:error, %Jido.Action.Error.InvalidInputError{}} = result
      end)
    end

    test "validates keyword params with non-atom keys" do
      capture_log(fn ->
        result = Chain.chain([{Add, [{"amount", 2}]}], %{value: 5})
        assert {:error, %Jido.Action.Error.InvalidInputError{}} = result
      end)
    end
  end

  describe "chain/3 run_action branch coverage" do
    test "handles {:ok, result, directive} action returns" do
      capture_log(fn ->
        assert {:ok, result} =
                 Chain.chain([OkWithDirectiveAction], %{base: true})

        assert result.base == true
        assert result.merged == true
      end)
    end

    test "handles {:error, error, directive} action returns" do
      capture_log(fn ->
        assert {:error, %Jido.Action.Error.ExecutionFailureError{} = error} =
                 Chain.chain([ErrorWithDirectiveAction], %{base: true})

        assert error.message =~ "with directive"
      end)
    end
  end
end
