defmodule JidoTest.ConfigAwaitTimeoutTest do
  use ExUnit.Case, async: false

  alias Jido.Action.Config

  setup do
    original_await_timeout = Application.get_env(:jido_action, :default_await_timeout)
    original_exec_timeout = Application.get_env(:jido_action, :default_timeout)

    on_exit(fn ->
      restore_env(:default_await_timeout, original_await_timeout)
      restore_env(:default_timeout, original_exec_timeout)
    end)

    :ok
  end

  test "await timeout falls back to await default and not exec timeout" do
    Application.delete_env(:jido_action, :default_await_timeout)
    Application.put_env(:jido_action, :default_timeout, 123)

    assert Config.await_timeout() == 5_000
  end

  test "await timeout uses explicit default_await_timeout when configured" do
    Application.put_env(:jido_action, :default_await_timeout, 750)
    Application.put_env(:jido_action, :default_timeout, 5_000)

    assert Config.await_timeout() == 750
  end

  defp restore_env(key, nil), do: Application.delete_env(:jido_action, key)
  defp restore_env(key, value), do: Application.put_env(:jido_action, key, value)
end
