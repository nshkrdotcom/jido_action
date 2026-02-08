defmodule Jido.Exec.Supervisors do
  @moduledoc """
  Resolves supervisor names based on instance configuration.

  This module provides instance isolation for Jido action execution.
  When a `jido:` option is provided, operations are routed to instance-scoped
  supervisors instead of the global `Jido.Action.TaskSupervisor`.

  ## Usage

  By default (no `jido:` option), the global supervisor is used:

      Jido.Exec.run(MyAction, %{}, %{})
      # Uses Jido.Action.TaskSupervisor

  With instance isolation:

      Jido.Exec.run(MyAction, %{}, %{}, jido: MyApp.Jido)
      # Uses MyApp.Jido.TaskSupervisor

  ## Instance Supervisor Naming Convention

  When `jido: MyApp.Jido` is provided, supervisors are resolved as:
  - TaskSupervisor: `MyApp.Jido.TaskSupervisor`

  `:jido` should be a compile-time known module atom from your application.
  Avoid passing arbitrary/user-derived module names.

  The instance supervisors must be started as part of your application's
  supervision tree before use.
  """

  @doc """
  Returns the TaskSupervisor name to use based on options.

  ## Options

  - `:jido` - Optional instance name (atom). When provided, returns the
    instance-scoped TaskSupervisor. When absent, returns the global supervisor.
    This should be a known module atom (for example `MyApp.Jido`).

  ## Returns

  The supervisor name as an atom.

  ## Raises

  - `ArgumentError` if `:jido` option is not an atom.

  ## Examples

      iex> Jido.Exec.Supervisors.task_supervisor([])
      Jido.Action.TaskSupervisor

      iex> Jido.Exec.Supervisors.task_supervisor(jido: MyApp.Jido)
      MyApp.Jido.TaskSupervisor

  """
  @spec task_supervisor(keyword()) :: atom()
  def task_supervisor(opts) when is_list(opts) do
    case Keyword.fetch(opts, :jido) do
      :error ->
        Jido.Action.TaskSupervisor

      {:ok, nil} ->
        Jido.Action.TaskSupervisor

      {:ok, jido} when is_atom(jido) ->
        Module.concat(jido, TaskSupervisor)

      {:ok, other} ->
        raise ArgumentError,
              "Expected :jido option to be an atom (module), got: #{inspect(other)}"
    end
  end

  def task_supervisor(opts) do
    raise ArgumentError,
          "Expected opts to be a keyword list, got: #{inspect(opts)}"
  end

  @doc """
  Returns the TaskSupervisor name without validating that it's running.

  Use this when you need to resolve the supervisor name but don't want to
  raise if it's not running (e.g., for testing or introspection).

  ## Examples

      iex> Jido.Exec.Supervisors.task_supervisor_name([])
      Jido.Action.TaskSupervisor

      iex> Jido.Exec.Supervisors.task_supervisor_name(jido: MyApp.Jido)
      MyApp.Jido.TaskSupervisor

  """
  @spec task_supervisor_name(keyword()) :: atom()
  def task_supervisor_name(opts) when is_list(opts) do
    case Keyword.fetch(opts, :jido) do
      :error ->
        Jido.Action.TaskSupervisor

      {:ok, nil} ->
        Jido.Action.TaskSupervisor

      {:ok, jido} when is_atom(jido) ->
        Module.concat(jido, TaskSupervisor)

      {:ok, other} ->
        raise ArgumentError,
              "Expected :jido option to be an atom (module), got: #{inspect(other)}"
    end
  end
end
