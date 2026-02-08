defmodule JidoTest.ExecHardeningTest do
  use JidoTest.ActionCase, async: false

  alias Jido.Action.Error
  alias Jido.Exec
  alias Jido.Exec.Chain
  alias JidoTest.TestActions.BasicAction
  alias JidoTest.TestActions.DelayAction

  @moduletag :capture_log

  defmodule MapDirectiveErrorAction do
    use Jido.Action,
      name: "map_directive_error_action",
      description: "Returns non-exception error reason with directive"

    @impl true
    def run(_params, _context) do
      {:error, %{kind: :map_reason}, %{directive: true}}
    end
  end

  defmodule HookErrorAction do
    use Jido.Action,
      name: "hook_error_action",
      description: "Returns non-exception hook validation error",
      schema: [value: [type: :integer]]

    @impl true
    def on_before_validate_params(_params), do: {:error, :bad_hook_return}

    @impl true
    def run(_params, _context), do: {:ok, %{ok: true}}
  end

  defmodule CompensationTimeoutPrecedenceAction do
    use Jido.Action,
      name: "comp_timeout_precedence_action",
      description: "Captures compensation options for timeout precedence assertions",
      compensation: [enabled: true, timeout: 250]

    @impl true
    def run(_params, _context), do: {:error, Error.execution_error("boom")}

    @impl true
    def on_error(params, _error, _context, opts) do
      send(params.capture_pid, {:comp_opts, opts})
      {:ok, %{compensated: true}}
    end
  end

  describe "async monitor lifecycle" do
    test "run_async returns monitor metadata and owner" do
      async_ref = Exec.run_async(BasicAction, %{value: 42})

      assert is_reference(async_ref.monitor_ref)
      assert async_ref.owner == self()
      assert is_pid(async_ref.pid)
      assert is_reference(async_ref.ref)
    end

    test "await clears monitor down message on success" do
      async_ref = Exec.run_async(BasicAction, %{value: 5})
      monitor_ref = async_ref.monitor_ref
      pid = async_ref.pid

      assert {:ok, %{value: 5}} = Exec.await(async_ref, 500)
      refute_receive {:DOWN, ^monitor_ref, :process, ^pid, _}, 50
    end

    test "cancel clears monitor down message" do
      async_ref = Exec.run_async(DelayAction, %{delay: 2_000}, %{}, timeout: 2_500)
      monitor_ref = async_ref.monitor_ref
      pid = async_ref.pid

      assert :ok = Exec.cancel(async_ref)
      refute_receive {:DOWN, ^monitor_ref, :process, ^pid, _}, 50
    end
  end

  describe "error normalization" do
    test "normalizes 3-tuple non-exception errors while preserving directive" do
      assert {:error, %Error.ExecutionFailureError{} = error, %{directive: true}} =
               Exec.run(MapDirectiveErrorAction, %{}, %{})

      assert error.details.reason == %{kind: :map_reason}
    end

    test "normalizes non-exception hook validation errors" do
      assert {:error, %Error.InvalidInputError{} = error} = Exec.run(HookErrorAction, %{}, %{})
      assert error.message =~ "bad_hook_return"
    end
  end

  describe "compensation timeout precedence" do
    test "compensation_timeout option overrides execution timeout and metadata timeout" do
      assert {:error, %Error.ExecutionFailureError{}} =
               Exec.run(
                 CompensationTimeoutPrecedenceAction,
                 %{capture_pid: self()},
                 %{},
                 timeout: 1_000,
                 compensation_timeout: 42
               )

      assert_receive {:comp_opts, opts}
      assert opts[:compensation_timeout] == 42
      assert opts[:timeout] == 1_000
    end
  end

  describe "chain async supervision" do
    test "routes async chain task to instance supervisor when jido option is provided" do
      start_supervised!({Task.Supervisor, name: HardeningInstance.TaskSupervisor})

      task =
        Chain.chain(
          [DelayAction],
          %{delay: 100},
          async: true,
          jido: HardeningInstance
        )

      assert task.pid in Task.Supervisor.children(HardeningInstance.TaskSupervisor)
      assert {:ok, result} = Chain.await(task, 1_000)
      assert result.delay == 100
      assert result.result == "Async action completed"
    end
  end
end
