defmodule JidoTest.Exec.TaskHelperTest do
  use ExUnit.Case, async: false

  alias Jido.Exec.AsyncRef
  alias Jido.Exec.TaskHelper

  describe "spawn_monitored/3" do
    test "returns an async ref and delivers tagged result message" do
      assert {:ok, async_ref} =
               TaskHelper.spawn_monitored([], :task_helper_test_result, fn ->
                 :ok
               end)

      assert %AsyncRef{} = async_ref
      assert async_ref.owner == self()
      assert is_pid(async_ref.pid)
      assert is_reference(async_ref.ref)
      assert is_reference(async_ref.monitor_ref)
      assert async_ref.result_tag == :task_helper_test_result
      ref = async_ref.ref
      assert_receive {:task_helper_test_result, ^ref, :ok}
    end

    test "returns a descriptive error when instance supervisor is missing" do
      assert {:error, %ArgumentError{} = error} =
               TaskHelper.spawn_monitored([jido: Missing.Instance], :missing_supervisor, fn ->
                 :ok
               end)

      assert error.message =~ "Instance task supervisor"
      assert error.message =~ "Missing.Instance"
    end

    test "terminates the task when the owner process exits" do
      parent = self()

      owner =
        spawn(fn ->
          assert {:ok, async_ref} =
                   TaskHelper.spawn_monitored([], :task_helper_owner_exit, fn ->
                     Process.sleep(:infinity)
                   end)

          send(parent, {:spawned_task, async_ref.pid})
        end)

      assert is_pid(owner)
      assert_receive {:spawned_task, task_pid}, 500

      monitor_ref = Process.monitor(task_pid)
      assert_receive {:DOWN, ^monitor_ref, :process, ^task_pid, _reason}, 1_000
      refute Process.alive?(task_pid)
    end
  end

  describe "timeout_cleanup/6" do
    test "terminates child and flushes pending result/down messages" do
      task_supervisor = JidoTest.Exec.TaskHelperTimeoutSupervisor
      {:ok, supervisor_pid} = Task.Supervisor.start_link(name: task_supervisor)

      on_exit(fn ->
        if Process.alive?(supervisor_pid) do
          Process.exit(supervisor_pid, :shutdown)
        end
      end)

      {:ok, pid} =
        Task.Supervisor.start_child(task_supervisor, fn ->
          Process.sleep(:infinity)
        end)

      monitor_ref = Process.monitor(pid)
      ref = make_ref()
      send(self(), {:task_helper_timeout_result, ref, :late_result})

      assert :ok =
               TaskHelper.timeout_cleanup(
                 task_supervisor,
                 pid,
                 monitor_ref,
                 :task_helper_timeout_result,
                 ref,
                 down_grace_period_ms: 0,
                 flush_timeout_ms: 0,
                 max_flush_messages: 2
               )

      refute_received {:task_helper_timeout_result, ^ref, :late_result}
      refute Process.alive?(pid)
    end
  end
end
