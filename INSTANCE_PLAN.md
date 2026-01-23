# Jido Instance Isolation Plan

**Status: ✅ IMPLEMENTED**

## Goal

Enable instance isolation where:
- **Default API** uses global supervisors (zero config, works out of the box)
- **Instance API** routes all operations through instance-scoped supervisors

```elixir
# Global (default) - uses Jido.Action.TaskSupervisor
Jido.Exec.run(MyAction, %{}, %{})

# Instance-scoped - uses MyApp.Jido.TaskSupervisor
MyApp.Jido.start_agent(MyAgent, initial_state)
Jido.Exec.run(MyAction, %{}, %{}, jido: MyApp.Jido)
```

## Pattern

Naming convention:
- Functions with arity N use global supervisors
- Functions with arity N+1 accept instance name as first argument

## Isolation Scope

Instance-scoped resources:
- `Task.Supervisor` — async action execution
- `DynamicSupervisor` — agent process management  
- `Registry` — agent process lookup

## Key Invariant

When `jido: instance` is passed, **all** spawned tasks and processes route through that instance's supervisors. No silent fallback to globals within an instance context.

## Success Criteria

1. ✅ Existing code works unchanged (global supervisors)
2. ✅ Instance users get complete isolation with single `jido:` option
3. ✅ Cross-tenant task contention eliminated
4. ✅ Easy to test isolation guarantees

## Implementation Details

### Changes Made

#### jido_action package
- **New module**: `Jido.Exec.Supervisors` - Resolves TaskSupervisor name based on `jido:` option
- **Updated**: `Jido.Exec.run/4` - Uses `Supervisors.task_supervisor(opts)` for timeout task spawning
- **Updated**: `Jido.Exec.Async.start/4` - Uses `Supervisors.task_supervisor(opts)` for async task spawning
- **Updated**: `run_opts` type includes `jido: atom()`

#### jido package
- **Updated**: `Jido.AgentServer.State.from_options/3` - Injects `__jido__` into agent state
- **Updated**: `Jido.Agent.cmd/2` - Extracts `__jido__` from state and passes to instruction opts
- Agent directives already used `state.jido` for supervisor resolution

### How It Works

1. When `Jido.start_agent(instance, Agent, opts)` is called, the `jido:` option is set
2. `AgentServer.Options` validates and stores the jido instance
3. `AgentServer.State.from_options/3` injects `__jido__` into `agent.state`
4. When `cmd/2` runs, it extracts `__jido__` and passes it to instruction opts
5. Strategies call `Jido.Exec.run(instruction)` where opts include `jido:`
6. `Jido.Exec` uses `Supervisors.task_supervisor(opts)` to route to correct supervisor

### Tests Added

- `test/jido_action/exec_instance_isolation_test.exs` - Tests `Jido.Exec` isolation
- `test/jido/instance_isolation_test.exs` - End-to-end agent isolation tests
