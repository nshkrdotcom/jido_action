defmodule JidoTest.Exec.SupervisorsCoverageTest do
  @moduledoc """
  Coverage tests for Jido.Exec.Supervisors.
  """
  use ExUnit.Case, async: true

  alias Jido.Exec.Supervisors

  describe "task_supervisor/1" do
    test "returns global supervisor when no jido option" do
      assert Supervisors.task_supervisor([]) == Jido.Action.TaskSupervisor
    end

    test "returns global supervisor when jido is nil" do
      assert Supervisors.task_supervisor(jido: nil) == Jido.Action.TaskSupervisor
    end

    test "returns instance supervisor when jido is an atom" do
      assert Supervisors.task_supervisor(jido: MyApp.Jido) == MyApp.Jido.TaskSupervisor
    end

    test "returns explicitly provided task supervisor when configured" do
      assert Supervisors.task_supervisor(task_supervisor: Custom.TaskSupervisor) ==
               Custom.TaskSupervisor
    end

    test "returns explicitly provided task supervisor pid when configured" do
      {:ok, task_supervisor} = Task.Supervisor.start_link()

      on_exit(fn ->
        if Process.alive?(task_supervisor) do
          Process.exit(task_supervisor, :shutdown)
        end
      end)

      assert Supervisors.task_supervisor(task_supervisor: task_supervisor) == task_supervisor
    end

    test "raises for non-atom jido option" do
      assert_raise ArgumentError, ~r/Expected :jido option to be an atom/, fn ->
        Supervisors.task_supervisor(jido: "not_an_atom")
      end
    end

    test "raises for non-keyword-list opts" do
      assert_raise ArgumentError, ~r/Expected opts to be a keyword list/, fn ->
        Supervisors.task_supervisor(:not_a_list)
      end
    end
  end

  describe "task_supervisor_name/1" do
    test "returns global supervisor name" do
      assert Supervisors.task_supervisor_name([]) == Jido.Action.TaskSupervisor
    end

    test "returns instance supervisor name" do
      assert Supervisors.task_supervisor_name(jido: MyApp.Jido) == MyApp.Jido.TaskSupervisor
    end

    test "returns global for nil jido" do
      assert Supervisors.task_supervisor_name(jido: nil) == Jido.Action.TaskSupervisor
    end

    test "raises for non-atom jido option" do
      assert_raise ArgumentError, fn ->
        Supervisors.task_supervisor_name(jido: 123)
      end
    end

    test "raises for atom that is not an Elixir module alias" do
      assert_raise ArgumentError, ~r/Elixir module atom/, fn ->
        Supervisors.task_supervisor_name(jido: :not_a_module_alias)
      end
    end
  end
end
