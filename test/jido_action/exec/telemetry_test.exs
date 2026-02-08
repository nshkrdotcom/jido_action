defmodule JidoTest.Exec.TelemetryTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Jido.Exec.Telemetry

  @moduletag :capture_log

  defmodule FakeAction do
    def __jido_action__, do: true
  end

  describe "emit_start_event/3" do
    test "emits [:jido, :action, :start] telemetry event" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-start-#{inspect(ref)}",
        [:jido, :action, :start],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      assert :ok = Telemetry.emit_start_event(FakeAction, %{value: 1}, %{user: "test"})

      assert_receive {:telemetry_event, [:jido, :action, :start], measurements, metadata}
      assert is_integer(measurements.system_time)
      assert metadata.action == FakeAction
      assert metadata.params == %{value: 1}
      assert metadata.context == %{user: "test"}

      :telemetry.detach("test-start-#{inspect(ref)}")
    end
  end

  describe "emit_end_event/4" do
    test "emits [:jido, :action, :stop] telemetry event" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-stop-#{inspect(ref)}",
        [:jido, :action, :stop],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      result = {:ok, %{value: 42}}

      assert :ok =
               Telemetry.emit_end_event(FakeAction, %{value: 1}, %{user: "test"}, result)

      assert_receive {:telemetry_event, [:jido, :action, :stop], measurements, metadata}
      assert is_integer(measurements.system_time)
      assert measurements.duration == 0
      assert metadata.action == FakeAction
      assert metadata.params == %{value: 1}
      assert metadata.context == %{user: "test"}
      assert metadata.result == result

      :telemetry.detach("test-stop-#{inspect(ref)}")
    end
  end

  describe "log_execution_start/3" do
    test "logs action execution start" do
      log =
        capture_log(fn ->
          Telemetry.log_execution_start(FakeAction, %{value: 1}, %{user: "test"})
        end)

      assert log =~ "Executing"
      assert log =~ "FakeAction"
    end
  end

  describe "log_execution_end/4" do
    test "logs successful result with ok tuple" do
      log =
        capture_log(fn ->
          Telemetry.log_execution_end(FakeAction, %{}, %{}, {:ok, %{value: 42}})
        end)

      assert log =~ "Finished execution"
      assert log =~ "FakeAction"
    end

    test "logs successful result with ok+directive tuple" do
      log =
        capture_log(fn ->
          Telemetry.log_execution_end(FakeAction, %{}, %{}, {:ok, %{value: 42}, :some_directive})
        end)

      assert log =~ "Finished execution"
      assert log =~ "directive"
    end

    test "logs error result" do
      log =
        capture_log(fn ->
          Telemetry.log_execution_end(FakeAction, %{}, %{}, {:error, "something went wrong"})
        end)

      assert log =~ "failed"
      assert log =~ "something went wrong"
    end

    test "logs error result with directive" do
      log =
        capture_log(fn ->
          Telemetry.log_execution_end(
            FakeAction,
            %{},
            %{},
            {:error, "failure", :rollback_directive}
          )
        end)

      assert log =~ "failed"
      assert log =~ "directive"
    end

    test "logs unexpected result format" do
      log =
        capture_log(fn ->
          Telemetry.log_execution_end(FakeAction, %{}, %{}, :unexpected_result)
        end)

      assert log =~ "Finished execution"
      assert log =~ "unexpected_result"
    end
  end

  describe "extract_safe_error_message/1" do
    test "extracts nested message" do
      error = %{message: %{message: "inner error"}}
      assert Telemetry.extract_safe_error_message(error) == "inner error"
    end

    test "returns empty string for nil message" do
      error = %{message: nil}
      assert Telemetry.extract_safe_error_message(error) == ""
    end

    test "returns binary message directly" do
      error = %{message: "direct error"}
      assert Telemetry.extract_safe_error_message(error) == "direct error"
    end

    test "handles struct with message field" do
      error = %{message: %RuntimeError{message: "runtime error"}}
      assert Telemetry.extract_safe_error_message(error) == "runtime error"
    end

    test "inspects struct without message field" do
      error = %{message: %URI{host: "example.com"}}
      result = Telemetry.extract_safe_error_message(error)
      assert is_binary(result)
      assert result =~ "example.com"
    end

    test "inspects unknown error formats" do
      assert Telemetry.extract_safe_error_message(:some_atom) == ":some_atom"
      assert Telemetry.extract_safe_error_message(42) == "42"
      assert Telemetry.extract_safe_error_message("plain string") == "\"plain string\""
    end
  end

  describe "cond_log_start/4" do
    test "logs when threshold allows" do
      log =
        capture_log(fn ->
          Telemetry.cond_log_start(:debug, FakeAction, %{value: 1}, %{})
        end)

      assert log =~ "Executing"
      assert log =~ "FakeAction"
    end
  end

  describe "cond_log_end/3" do
    test "logs ok result" do
      log =
        capture_log(fn ->
          Telemetry.cond_log_end(:debug, FakeAction, {:ok, %{value: 42}})
        end)

      assert log =~ "Finished execution"
    end

    test "logs ok+directive result" do
      log =
        capture_log(fn ->
          Telemetry.cond_log_end(:debug, FakeAction, {:ok, %{v: 1}, :directive})
        end)

      assert log =~ "Finished execution"
      assert log =~ "directive"
    end

    test "logs error result" do
      log =
        capture_log(fn ->
          Telemetry.cond_log_end(:debug, FakeAction, {:error, "oops"})
        end)

      assert log =~ "failed"
    end

    test "logs error+directive result" do
      log =
        capture_log(fn ->
          Telemetry.cond_log_end(:debug, FakeAction, {:error, "oops", :rollback})
        end)

      assert log =~ "failed"
      assert log =~ "directive"
    end

    test "logs unexpected result" do
      log =
        capture_log(fn ->
          Telemetry.cond_log_end(:debug, FakeAction, :weird_result)
        end)

      assert log =~ "Finished execution"
      assert log =~ "weird_result"
    end
  end

  describe "cond_log_error/3" do
    test "logs action error" do
      log =
        capture_log(fn ->
          Telemetry.cond_log_error(:debug, FakeAction, "something broke")
        end)

      assert log =~ "failed"
      assert log =~ "something broke"
    end
  end

  describe "cond_log_retry/5" do
    test "logs retry attempt" do
      log =
        capture_log(fn ->
          Telemetry.cond_log_retry(:debug, FakeAction, 2, 5, 1000)
        end)

      assert log =~ "Retrying"
      assert log =~ "3/5"
      assert log =~ "1000ms"
    end
  end

  describe "cond_log_message/3" do
    test "logs arbitrary message at specified level" do
      log =
        capture_log(fn ->
          Telemetry.cond_log_message(:debug, :info, "custom message here")
        end)

      assert log =~ "custom message here"
    end
  end

  describe "cond_log_function_error/2" do
    test "logs function invocation error" do
      log =
        capture_log(fn ->
          Telemetry.cond_log_function_error(:debug, %{message: "bad function"})
        end)

      assert log =~ "Function invocation error"
      assert log =~ "bad function"
    end
  end

  describe "cond_log_unexpected_error/2" do
    test "logs unexpected error" do
      log =
        capture_log(fn ->
          Telemetry.cond_log_unexpected_error(:debug, %{message: "unexpected"})
        end)

      assert log =~ "Unexpected error"
      assert log =~ "unexpected"
    end
  end

  describe "cond_log_caught_error/2" do
    test "logs caught throw/exit" do
      log =
        capture_log(fn ->
          Telemetry.cond_log_caught_error(:debug, %{message: "caught it"})
        end)

      assert log =~ "Caught unexpected throw/exit"
      assert log =~ "caught it"
    end
  end

  describe "cond_log_execution_debug/4" do
    test "logs execution debug info" do
      log =
        capture_log(fn ->
          Telemetry.cond_log_execution_debug(:debug, FakeAction, %{v: 1}, %{ctx: true})
        end)

      assert log =~ "Starting execution"
      assert log =~ "FakeAction"
    end
  end

  describe "cond_log_validation_failure/3" do
    test "logs validation failure" do
      log =
        capture_log(fn ->
          Telemetry.cond_log_validation_failure(:debug, FakeAction, "field is required")
        end)

      assert log =~ "output validation failed"
      assert log =~ "field is required"
    end
  end

  describe "cond_log_failure/2" do
    test "logs execution failure" do
      log =
        capture_log(fn ->
          Telemetry.cond_log_failure(:debug, "timeout exceeded")
        end)

      assert log =~ "Action Execution failed"
      assert log =~ "timeout exceeded"
    end
  end
end
