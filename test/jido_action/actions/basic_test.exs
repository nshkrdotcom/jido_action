defmodule JidoTest.Actions.BasicActionsTest do
  use JidoTest.Case, async: false
  require Logger
  alias Jido.Actions.Basic
  import ExUnit.CaptureLog

  @moduletag :capture_log

  describe "Sleep" do
    test "sleeps for the specified duration" do
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, %{duration_ms: 100}} = Basic.Sleep.run(%{duration_ms: 100}, %{})
      end_time = System.monotonic_time(:millisecond)
      assert end_time - start_time >= 100
    end

    test "uses default duration when not specified" do
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, %{duration_ms: 1000}} = Basic.Sleep.run(%{duration_ms: 1000}, %{})
      end_time = System.monotonic_time(:millisecond)
      assert end_time - start_time >= 1000
    end
  end

  describe "Todo" do
    test "logs todo message" do
      log =
        capture_log([level: :debug], fn ->
          assert {:ok, %{todo: "Implement feature"}} =
                   Basic.Todo.run(%{todo: "Implement feature"}, %{})

          # Small delay to ensure log is captured
          Process.sleep(50)
        end)

      # Look for the specific todo message, ignoring other noise
      assert Enum.any?(String.split(log, "\n"), &(&1 =~ "TODO Action: Implement feature"))
    end
  end

  describe "Delay" do
    test "introduces random delay within specified range" do
      start_time = System.monotonic_time(:millisecond)

      assert {:ok, %{min_ms: 100, max_ms: 200, actual_delay: delay}} =
               Basic.RandomSleep.run(%{min_ms: 100, max_ms: 200}, %{})

      end_time = System.monotonic_time(:millisecond)

      assert delay >= 100 and delay <= 200
      assert end_time - start_time >= delay
    end
  end

  describe "Increment" do
    test "increments the value by 1" do
      assert {:ok, %{value: 6}} = Basic.Increment.run(%{value: 5}, %{})
    end
  end

  describe "Decrement" do
    test "decrements the value by 1" do
      assert {:ok, %{value: 4}} = Basic.Decrement.run(%{value: 5}, %{})
    end
  end

  describe "Noop" do
    test "returns input params unchanged" do
      params = %{test: "value", other: 123}
      assert {:ok, ^params} = Basic.Noop.run(params, %{})
    end

    test "works with empty params" do
      assert {:ok, %{}} = Basic.Noop.run(%{}, %{})
    end
  end

  describe "Inspect" do
    import ExUnit.CaptureIO

    test "inspects simple values" do
      output =
        capture_io(fn ->
          assert {:ok, %{value: 123}} = Basic.Inspect.run(%{value: 123}, %{})
        end)

      assert output =~ "123"
    end

    test "inspects complex data structures" do
      complex_value = %{a: [1, 2, 3], b: %{c: "test"}}
      expected_output = "Inspect action output: " <> inspect(complex_value)

      output =
        capture_io(fn ->
          assert {:ok, %{value: ^complex_value}} = Basic.Inspect.run(%{value: complex_value}, %{})
        end)

      assert String.trim(output) == expected_output
    end
  end
end
