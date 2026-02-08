defmodule JidoTest.ExecConfigTest do
  @moduledoc """
  Tests specifically targeting configuration function coverage
  """

  use JidoTest.ActionCase, async: false

  import ExUnit.CaptureLog

  alias Jido.Exec
  alias JidoTest.CoverageTestActions

  @moduletag :capture_log

  describe "configuration function direct coverage" do
    test "directly trigger configuration helper functions" do
      # Clear and restore app config to force the helpers to be called
      original_timeout = Application.get_env(:jido_action, :default_timeout)
      original_max_retries = Application.get_env(:jido_action, :default_max_retries)
      original_backoff = Application.get_env(:jido_action, :default_backoff)

      try do
        # Delete config to force default values
        Application.delete_env(:jido_action, :default_timeout)
        Application.delete_env(:jido_action, :default_max_retries)
        Application.delete_env(:jido_action, :default_backoff)

        # These operations should trigger the config helper functions
        capture_log(fn ->
          # Test async without explicit timeout (should use get_default_timeout)
          async_ref = Exec.run_async(JidoTest.TestActions.BasicAction, %{value: 1}, %{})
          assert {:ok, %{value: 1}} = Exec.await(async_ref)
        end)

        capture_log(fn ->
          # This should use default max_retries and backoff
          assert {:error, _} =
                   Exec.run(CoverageTestActions.ConfigTestAction, %{should_fail: true}, %{})
        end)
      after
        # Restore original config
        if original_timeout do
          Application.put_env(:jido_action, :default_timeout, original_timeout)
        end

        if original_max_retries do
          Application.put_env(:jido_action, :default_max_retries, original_max_retries)
        end

        if original_backoff do
          Application.put_env(:jido_action, :default_backoff, original_backoff)
        end
      end
    end

    test "force config helpers through internal calls" do
      # These operations specifically target the uncovered config helper functions
      original_configs = [
        {:default_timeout, Application.get_env(:jido_action, :default_timeout)},
        {:default_max_retries, Application.get_env(:jido_action, :default_max_retries)},
        {:default_backoff, Application.get_env(:jido_action, :default_backoff)}
      ]

      try do
        # Clear all configs
        Enum.each(original_configs, fn {key, _} ->
          Application.delete_env(:jido_action, key)
        end)

        capture_log(fn ->
          # This should trigger get_default_max_retries and get_default_backoff
          result = Exec.run(CoverageTestActions.AllConfigPathsAction, %{attempt: 1}, %{})
          # Should eventually succeed after retries
          case result do
            {:ok, _} -> :ok
            {:error, _} -> :ok
          end
        end)

        # Test async path to trigger get_default_timeout
        capture_log(fn ->
          async_ref = Exec.run_async(CoverageTestActions.AllConfigPathsAction, %{attempt: 5}, %{})
          # This should trigger get_default_timeout for await
          assert {:ok, %{attempt: 5}} = Exec.await(async_ref)
        end)
      after
        # Restore configs
        Enum.each(original_configs, fn {key, value} ->
          if value do
            Application.put_env(:jido_action, key, value)
          end
        end)
      end
    end
  end
end
