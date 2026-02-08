defmodule JidoTest.ConfigGracePeriodsTest do
  use ExUnit.Case, async: false

  alias Jido.Action.Config

  @grace_config [
    {:async_down_grace_period_ms, :async_down_grace_period_ms, 100},
    {:async_shutdown_grace_period_ms, :async_shutdown_grace_period_ms, 1_000},
    {:chain_down_grace_period_ms, :chain_down_grace_period_ms, 100},
    {:chain_shutdown_grace_period_ms, :chain_shutdown_grace_period_ms, 1_000},
    {:compensation_down_grace_period_ms, :compensation_down_grace_period_ms, 100},
    {:exec_down_grace_period_ms, :exec_down_grace_period_ms, 100},
    {:mailbox_flush_timeout_ms, :mailbox_flush_timeout_ms, 0}
  ]

  setup do
    original =
      Enum.into(@grace_config, %{}, fn {env_key, _getter, _default} ->
        {env_key, Application.get_env(:jido_action, env_key)}
      end)

    on_exit(fn ->
      Enum.each(original, fn {env_key, value} ->
        if is_nil(value) do
          Application.delete_env(:jido_action, env_key)
        else
          Application.put_env(:jido_action, env_key, value)
        end
      end)
    end)

    :ok
  end

  test "returns defaults for grace period config" do
    Enum.each(@grace_config, fn {env_key, getter, default} ->
      Application.delete_env(:jido_action, env_key)
      assert apply(Config, getter, []) == default
    end)
  end

  test "returns environment overrides for grace period config" do
    Enum.with_index(@grace_config, 1)
    |> Enum.each(fn {{env_key, getter, _default}, index} ->
      override = 10 * index
      Application.put_env(:jido_action, env_key, override)
      assert apply(Config, getter, []) == override
    end)
  end

  test "mailbox flush max messages supports integer and :infinity" do
    original = Application.get_env(:jido_action, :mailbox_flush_max_messages)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:jido_action, :mailbox_flush_max_messages)
      else
        Application.put_env(:jido_action, :mailbox_flush_max_messages, original)
      end
    end)

    Application.delete_env(:jido_action, :mailbox_flush_max_messages)
    assert Config.mailbox_flush_max_messages() == :infinity

    Application.put_env(:jido_action, :mailbox_flush_max_messages, 25)
    assert Config.mailbox_flush_max_messages() == 25
  end

  test "timeout_zero_mode supports :legacy_direct and :immediate_timeout" do
    original = Application.get_env(:jido_action, :timeout_zero_mode)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:jido_action, :timeout_zero_mode)
      else
        Application.put_env(:jido_action, :timeout_zero_mode, original)
      end
    end)

    Application.delete_env(:jido_action, :timeout_zero_mode)
    assert Config.timeout_zero_mode() == :legacy_direct

    Application.put_env(:jido_action, :timeout_zero_mode, :immediate_timeout)
    assert Config.timeout_zero_mode() == :immediate_timeout

    Application.put_env(:jido_action, :timeout_zero_mode, :legacy_direct)
    assert Config.timeout_zero_mode() == :legacy_direct
  end

  test "validate! rejects invalid timeout_zero_mode value" do
    original = Application.get_env(:jido_action, :timeout_zero_mode)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:jido_action, :timeout_zero_mode)
      else
        Application.put_env(:jido_action, :timeout_zero_mode, original)
      end
    end)

    Application.put_env(:jido_action, :timeout_zero_mode, :invalid_mode)

    assert_raise ArgumentError,
                 ~r/timeout_zero_mode must be :legacy_direct or :immediate_timeout/,
                 fn ->
                   Config.validate!()
                 end
  end
end
