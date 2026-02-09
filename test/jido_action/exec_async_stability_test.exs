defmodule JidoTest.ExecAsyncStabilityTest do
  use JidoTest.ActionCase, async: false

  import ExUnit.CaptureLog

  alias Jido.Action.Error
  alias Jido.Exec
  alias JidoTest.TestActions.DelayAction

  @moduletag :capture_log

  defmodule BlockingAction do
    @moduledoc false
    use Jido.Action, name: "exec_async_stability_blocking", schema: []

    @impl true
    def run(_params, _context) do
      receive do
        :never -> {:ok, %{}}
      end
    end
  end

  describe "DOWN/result race handling" do
    test "await succeeds when DOWN arrives before result for normal exit" do
      capture_log(fn ->
        for _ <- 1..20 do
          parent = self()
          ref = make_ref()

          {:ok, pid} =
            Task.start(fn ->
              spawn(fn ->
                Process.sleep(5)
                send(parent, {:action_async_result, ref, {:ok, %{race: :resolved}}})
              end)

              :ok
            end)

          assert {:ok, %{race: :resolved}} = Exec.await(%{ref: ref, pid: pid}, 200)
        end
      end)
    end
  end

  describe "timeout cleanup" do
    test "await timeout stops task and leaves no stray result messages for ref" do
      capture_log(fn ->
        async_ref = Exec.run_async(DelayAction, %{delay: 500}, %{}, timeout: 5_000)
        ref = async_ref.ref

        assert {:error, %Error.TimeoutError{} = error} = Exec.await(async_ref, 30)
        assert Exception.message(error) =~ "Async action timed out after 30ms"

        Process.sleep(20)
        refute Process.alive?(async_ref.pid)
        refute_receive {:action_async_result, ^ref, _}, 50
      end)
    end
  end

  describe "cancel cleanup" do
    test "cancel is idempotent and await after cancel is deterministic" do
      capture_log(fn ->
        async_ref = Exec.run_async(BlockingAction, %{}, %{}, timeout: 5_000)
        ref = async_ref.ref

        assert :ok = Exec.cancel(async_ref)
        assert :ok = Exec.cancel(async_ref)

        Process.sleep(20)
        refute Process.alive?(async_ref.pid)

        assert {:error, error} = Exec.await(async_ref, 50)
        assert is_exception(error)
        refute_receive {:action_async_result, ^ref, _}, 20
      end)
    end
  end

  describe "bounded mailbox flushing" do
    test "timeout cleanup completes quickly with noisy mailbox" do
      capture_log(fn ->
        for i <- 1..5000 do
          send(self(), {:exec_noise, i})
        end

        async_ref = Exec.run_async(DelayAction, %{delay: 500}, %{}, timeout: 5_000)
        started_at = System.monotonic_time(:millisecond)

        assert {:error, %Error.TimeoutError{}} = Exec.await(async_ref, 20)

        elapsed_ms = System.monotonic_time(:millisecond) - started_at
        assert elapsed_ms < 800
      end)
    end
  end
end
