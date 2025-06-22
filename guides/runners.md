# Understanding Jido Runners

Runners are the execution engines that power Jido's agent system, responsible for processing instructions and managing state transitions. This guide explores both built-in runners and how to create custom implementations.

## Core Concepts

Runners serve as the bridge between agent instructions and their execution. They handle:

- Instruction processing
- State management
- Directive handling
- Error recovery
- Context propagation

## Built-in Runners

Jido provides two built-in runners optimized for different use cases:

### Simple Runner

The Simple Runner processes one instruction at a time, providing atomic execution and clear state transitions.

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "simple_example",
    runner: Jido.Runner.Simple
end
```

#### Key Features

- Single instruction execution
- Atomic state updates
- Clear error boundaries
- Predictable behavior

#### State Flow

```elixir
# Simple Runner execution flow
{:ok, agent, directives} = Jido.Runner.Simple.run(agent, opts)

# Internal process:
# 1. Dequeue single instruction
# 2. Execute via action module
# 3. Update state atomically
# 4. Process any directives
# 5. Return updated agent
```

### Chain Runner

The Chain Runner enables sequential execution of multiple instructions with state flowing between steps.

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "chain_example",
    runner: Jido.Runner.Chain
end
```

#### Key Features

- Sequential instruction processing
- State flows between steps
- Directive accumulation
- Comprehensive error handling

#### State Flow

```elixir
# Chain Runner execution flow
{:ok, agent, directives} = Jido.Runner.Chain.run(agent, opts)

# Internal process:
# 1. Convert queue to instruction list
# 2. Execute instructions sequentially
# 3. Flow state between steps
# 4. Accumulate directives
# 5. Apply final state
```

## Context and State Management

Both runners handle agent state through context propagation:

```elixir
# State is automatically included in context
def run(%{action: action, params: params, context: context}, _opts) do
  # Context includes agent state
  enhanced_context = Map.put(context, :state, agent.state)

  case Jido.Workflow.run(action, params, enhanced_context) do
    {:ok, result} -> handle_success(result)
    {:error, reason} -> handle_error(reason)
  end
end
```

## Directive Processing

Runners handle directives that modify agent behavior:

```elixir
# Example directive processing
defp handle_directive_result(agent, state_map, directives) do
  case Directive.apply_agent_directive(agent, directives) do
    {:ok, updated_agent, server_directives} ->
      {:ok, updated_agent, server_directives}

    {:error, reason} ->
      {:error, Error.validation_error("Invalid directive", reason)}
  end
end
```

## Creating Custom Runners

Implement the `Jido.Runner` behavior to create custom runners:

```elixir
defmodule MyCustomRunner do
  @behaviour Jido.Runner

  @impl true
  def run(agent, opts \\ []) do
    # Custom execution logic here
    # Must return {:ok, updated_agent, directives} | {:error, reason}
  end

  # Helper functions
  defp process_instructions(instructions, agent) do
    # Custom instruction processing
  end

  defp update_agent_state(agent, result) do
    # Custom state update logic
  end
end
```

### Implementation Guidelines

1. **State Management**

   - Handle state updates atomically
   - Preserve agent state on errors
   - Validate state transitions

2. **Error Handling**

   - Implement comprehensive error handling
   - Provide clear error messages
   - Consider retry strategies

3. **Directive Support**

   - Process directives consistently
   - Validate directive types
   - Handle directive errors gracefully

4. **Performance**
   - Consider concurrency implications
   - Optimize for your use case
   - Handle resource cleanup

## Integration with Agents

Runners are automatically integrated into Agents when specified in the configuration. This means you typically won't interact with runners directly, but rather through the Agent interface:

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "example_agent",
    runner: Jido.Runner.Chain  # Runner is automatically integrated

  # All runner operations are handled internally
  def process_workflow(data) do
    enqueue(ProcessData, %{input: data})
  end
end
```

This guide serves primarily as a reference for understanding runner behavior and creating custom implementations when needed.

## Best Practices

1. **Choose the Right Runner**

   - Use Simple Runner for atomic operations
   - Use Chain Runner for complex workflows
   - Create custom runners for specific needs

2. **State Management**

   - Keep state transitions explicit
   - Validate state changes
   - Handle edge cases

3. **Error Handling**

   - Implement comprehensive error handling
   - Provide clear error messages
   - Consider recovery strategies

4. **Testing**
   - Test happy paths thoroughly
   - Test error conditions
   - Test state transitions
   - Test directive handling

## Next Steps

- Explore the source code of built-in runners
- Implement custom runners for specific needs
- Contribute improvements to the community

Remember that runners are a critical part of your agent system. Choose and implement them carefully based on your specific requirements.
