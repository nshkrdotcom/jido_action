defmodule JidoTest.TaskHelperTest do
  use ExUnit.Case, async: true

  alias Jido.Exec.TaskHelper

  describe "await_result/4" do
    test "treats :noproc DOWN like normal and still accepts a late result" do
      parent = self()
      ref = make_ref()

      pid =
        spawn(fn ->
          :ok
        end)

      send(parent, {:DOWN, make_ref(), :process, pid, :noproc})

      spawn(fn ->
        Process.sleep(5)
        send(parent, {:task_helper_result, ref, {:ok, %{race: :resolved}}})
      end)

      assert {:ok, {:ok, %{race: :resolved}}} =
               TaskHelper.await_result(
                 %{pid: pid, ref: ref, monitor_ref: :any},
                 :task_helper_result,
                 100,
                 normal_exit_result_grace_ms: 50
               )
    end
  end
end
