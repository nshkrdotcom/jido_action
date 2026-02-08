defmodule JidoTest.ExecRetryPolicyTest do
  use JidoTest.ActionCase, async: true

  alias Jido.Action.Error
  alias Jido.Exec.Retry

  @moduletag :capture_log

  describe "should_retry?/4 policy" do
    test "test environment defaults retries to zero" do
      assert Application.get_env(:jido_action, :default_max_retries) == 0
    end

    test "InvalidInputError never retries" do
      error = {:error, Error.validation_error("invalid input")}

      refute Retry.should_retry?(error, 0, 3, [])
    end

    test "ConfigurationError never retries" do
      error = {:error, Error.config_error("bad configuration")}

      refute Retry.should_retry?(error, 0, 3, [])
    end

    test "ExecutionFailureError with keyword retry false never retries" do
      error = {:error, Error.execution_error("transient maybe", retry: false)}

      refute Retry.should_retry?(error, 0, 3, [])
    end

    test "ExecutionFailureError with map retry false never retries" do
      error = {:error, Error.execution_error("transient maybe", %{retry: false})}

      refute Retry.should_retry?(error, 0, 3, [])
    end

    test "ExecutionFailureError with keyword retry true is retryable" do
      error = {:error, Error.execution_error("transient maybe", retry: true)}

      assert Retry.should_retry?(error, 0, 3, [])
    end

    test "no retry hint remains retryable when retries remain" do
      error = {:error, Error.execution_error("no hint provided")}

      assert Retry.should_retry?(error, 0, 1, [])
    end
  end
end
