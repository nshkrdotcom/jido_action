Of course. Here are the detailed architectural diagrams and explanations for the `jido_action` codebase.

### Introduction

The `jido_action` library provides a framework for defining, executing, and composing discrete units of work called **Actions**. The architecture is designed to be robust, featuring synchronous and asynchronous execution, error handling with retries and compensation, compile-time validation, and integration points for external systems like AI agents.

The core components are:
*   **`Jido.Action`**: A behavior and macro (`use Jido.Action`) for defining new actions. It standardizes an action's metadata, input/output schemas, and lifecycle callbacks.
*   **`Jido.Instruction`**: A standardized data structure representing a "work order." It wraps an `Action` with its specific `params`, `context`, and `opts` for execution.
*   **`Jido.Exec`**: The execution engine. It's the primary interface for running actions, handling the entire lifecycle including validation, timeouts, retries, telemetry, and asynchronous execution.
*   **Action Implementations**: Concrete modules (e.g., `Jido.Actions.Files`, `Jido.Actions.Arithmetic`) that `use Jido.Action` and implement the `run/2` logic.

---

### 1. High-Level Component Architecture

This diagram illustrates the main components of the `jido_action` framework and how they interact with each other and with external systems.

```mermaid
graph TD
    subgraph Client/User Space
        ClientApp[Client Application]
    end

    subgraph Jido Framework
        Exec[Jido.Exec]
        Instruction[Jido.Instruction]
        ActionBehaviour["Jido.Action (Behavior & Macro)"]
        Tool[Jido.Actions.Tool]
        Chain[Jido.Exec.Chain]
        App[JidoAction.Application]
        TaskSupervisor[Task.Supervisor]
    end

    subgraph Action Implementations
        FileActions[actions/files.ex]
        ArithmeticActions[actions/arithmetic.ex]
        WorkflowAction[actions/workflow.ex]
        OtherActions[...]
    end

    subgraph External Systems
        FileSystem[(File System)]
        APIs[(External APIs)]
        LLM[Large Language Model]
    end

    ClientApp -->|Runs| Exec
    ClientApp -->|Creates| Instruction

    Exec -->|Executes| ActionBehaviour
    Exec -->|Uses| TaskSupervisor
    Exec -- Takes --> Instruction
    Instruction -- Wraps --> ActionBehaviour

    Chain -->|Uses| Exec

    ActionBehaviour -- "Implemented by" --> FileActions
    ActionBehaviour -- "Implemented by" --> ArithmeticActions
    ActionBehaviour -- "Implemented by" --> WorkflowAction
    ActionBehaviour -- "Implemented by" --> OtherActions

    FileActions -->|Interacts with| FileSystem
    OtherActions -->|Interacts with| APIs

    App -->|Starts & Supervises| TaskSupervisor
    Tool -->|Reads metadata from| ActionBehaviour
    Tool -->|Generates Tool Definition for| LLM
    LLM -->|Invokes action via| Tool

    WorkflowAction -->|Executes a sequence of| ActionBehaviour

    %% Elixir-inspired styling
    classDef userLayer fill:#4e2a8e,stroke:#24292e,stroke-width:2px,color:#fff
    classDef coreAbstraction fill:#7c4dbd,stroke:#4e2a8e,stroke-width:2px,color:#fff
    classDef keyModule fill:#9b72d0,stroke:#4e2a8e,stroke-width:2px,color:#fff
    classDef clientLayer fill:#b89ce0,stroke:#4e2a8e,stroke-width:2px,color:#24292e
    classDef serviceLayer fill:#d4c5ec,stroke:#4e2a8e,stroke-width:1px,color:#24292e
    classDef externalSystem fill:#f5f5f5,stroke:#666,stroke-width:1px,color:#24292e
    classDef adapter fill:#fdfbf7,stroke:#4e2a8e,stroke-width:2px,color:#24292e

    class ClientApp userLayer
    class ActionBehaviour coreAbstraction
    class Exec,Instruction,Chain keyModule
    class Tool,App,TaskSupervisor serviceLayer
    class FileActions,ArithmeticActions,WorkflowAction,OtherActions adapter
    class FileSystem,APIs,LLM externalSystem

    %% Darker arrow styling for better visibility
    linkStyle default stroke:#24292e,stroke-width:2px
```

#### **Diagram Explanation:**

*   **Client Application**: The user of the framework. It interacts primarily with `Jido.Exec` to run actions and `Jido.Instruction` to define work orders.
*   **`Jido.Exec`**: The central execution engine. It's the main entry point for running any action. It uses a `Task.Supervisor` for asynchronous operations.
*   **`Jido.Instruction`**: A data structure that encapsulates an `Action` module along with its parameters and context, making actions portable.
*   **`Jido.Action` (Behavior & Macro)**: This is the heart of the framework. It's not a concrete module that gets called directly at runtime but a behavior that `Action Implementations` must adopt. The `use Jido.Action` macro injects common functionality like validation, metadata, and serialization into the action modules.
*   **Action Implementations**: These are the concrete Elixir modules (`jido_action/actions/*.ex`) that define the actual logic for a piece of work (e.g., writing a file, making an API call).
*   **`Jido.Exec.Chain`**: A utility that sits on top of `Jido.Exec` to run a sequence of actions, passing the output of one to the next.
*   **`Jido.Actions.Tool`**: A utility module that introspects an `Action`'s metadata and schema to generate a tool definition compatible with AI systems like OpenAI's function calling.
*   **OTP Integration**: The `JidoAction.Application` starts a `Task.Supervisor`, which is crucial for the asynchronous execution model provided by `Jido.Exec.run_async`.

---

### 2. Synchronous Action Execution Lifecycle

This sequence diagram details the steps involved when a client calls `Jido.Exec.run` to execute an action synchronously. It highlights the validation, execution, and error handling flow.

```mermaid
sequenceDiagram
    participant Client
    participant Exec as Jido.Exec
    participant MyAction as MyAction (e.g., actions/files.ex)
    participant Behaviour as Jido.Action Behaviour

    Client->>+Exec: run(MyAction, params, context, opts)
    Note over Exec: 1. Normalize params & context.
    Exec->>Exec: normalize_params(params)<br/>normalize_context(context)
    Note over Exec: 2. Validate the action module itself.
    Exec->>Exec: validate_action(MyAction)
    Note over Exec: 3. Validate input params against schema.
    Exec->>+MyAction: validate_params(normalized_params)
    MyAction->>+Behaviour: (internally calls do_validate_params)
    Behaviour-->>-MyAction: {:ok, validated_params}
    MyAction-->>-Exec: {:ok, validated_params}
    Note over Exec: 4. Execute with retries & timeout.
    Exec->>+Exec: do_run_with_retry(...)
    Exec->>Exec: execute_action_with_timeout(...)
    Exec->>+MyAction: run(validated_params, context)
    Note right of MyAction: Action's core logic is executed here.
    MyAction-->>-Exec: {:ok, result}
    Exec->>+MyAction: validate_output(result)
    MyAction->>+Behaviour: (internally calls do_validate_output)
    Behaviour-->>-MyAction: {:ok, validated_result}
    MyAction-->>-Exec: {:ok, validated_result}
    Exec-->>-Exec: (End retry loop)
    Exec-->>-Client: {:ok, validated_result}

    alt Error during parameter validation
        Exec->>MyAction: validate_params(invalid_params)
        MyAction-->>Exec: {:error, reason}
        Exec-->>Client: {:error, %Jido.Action.Error{type: :validation_error, ...}}
    end

    alt Error during execution
        Exec->>MyAction: run(params, context)
        MyAction-->>Exec: {:error, reason}
        Note over Exec: 5. Compensation logic is triggered if enabled.
        Exec->>MyAction: on_error(params, error, context)
        MyAction-->>Exec: {:ok, compensation_result}
        Exec-->>Client: {:error, %Jido.Action.Error{type: :compensation_error, ...}}
    end
```

#### **Diagram Explanation:**

1.  **Normalization**: `Jido.Exec` first normalizes the `params` and `context` into a standard map format.
2.  **Action Validation**: It ensures the provided module is a valid, compiled action that implements the required `run/2` function.
3.  **Parameter Validation**: `Jido.Exec` calls `MyAction.validate_params/1`. This function, injected by `use Jido.Action`, validates the parameters against the `schema` defined in the action.
4.  **Execution with Policies**: The core execution happens within helpers that manage:
    *   **Retries**: `do_run_with_retry` will re-run the action on failure, up to `max_retries`.
    *   **Timeouts**: `execute_action_with_timeout` wraps the call in a process that will be terminated if it exceeds the specified timeout.
    *   **Telemetry**: Events are emitted at the start and end of execution.
5.  **Core Logic**: The action's specific `run/2` function is finally called.
6.  **Output Validation**: The result from `run/2` is validated against the `output_schema` (if defined).
7.  **Error & Compensation**: If `run/2` returns an error, `Jido.Exec` checks if compensation is enabled. If so, it calls the `on_error/4` callback on the action module, allowing for cleanup or rollback logic. The final error returned to the client is a `compensation_error`.

---

### 3. Asynchronous Action Execution Flow

This diagram shows how `Jido.Exec.run_async` works, leveraging an OTP `Task.Supervisor` to run actions in background processes without blocking the client.

```mermaid
sequenceDiagram
    participant Client
    participant Exec as Jido.Exec
    participant Supervisor as Jido.Action.TaskSupervisor
    participant Task as Spawned Task Process

    Client->>+Exec: run_async(MyAction, params, opts)
    Note over Exec: 1. Spawns a task under the supervisor.
    Exec->>+Supervisor: start_child(fn -> ... end)
    Supervisor-->>-Exec: {:ok, pid}
    Note over Exec: 2. Monitors the task process.
    Exec->>Exec: Process.monitor(pid)
    Exec-->>-Client: returns async_ref %{ref: ..., pid: ...}

    activate Task
    Note right of Task: Task executes Jido.Exec.run (synchronous flow from Diagram 2).
    Task->>Task: result = Jido.Exec.run(...)
    Note over Task, Client: 3. Sends result back to the parent (Client).
    Task->>Client: send(self(), {:action_async_result, ref, result})
    deactivate Task

    Note over Client: ...Client does other work...

    Client->>+Exec: await(async_ref, timeout)
    Note over Exec: 4. Enters a receive block to wait for the result.
    Exec-->>Exec: receive do...
    Exec-->>-Client: {:ok, result}

    alt Task crashes
        Task->>Task: (crashes)
        Note over Exec, Client: Supervisor handles crash, monitor sends :DOWN message.
        Client->>+Exec: await(async_ref, timeout)
        Exec-->>Exec: receive {:DOWN, ..., reason}
        Exec-->>-Client: {:error, %Jido.Action.Error{type: :execution_error, ...}}
    end
```

#### **Diagram Explanation:**

1.  **Task Spawning**: `run_async` does not execute the action directly. Instead, it wraps the call to `Jido.Exec.run` in an anonymous function and passes it to `Task.Supervisor.start_child`. This creates a new process to do the work.
2.  **Monitoring**: The client's process (which called `run_async`) monitors the newly spawned task. This allows it to receive a `:DOWN` message if the task process crashes, preventing an indefinite wait.
3.  **Result Passing**: When the task finishes its work, it sends the result in a message tagged with a unique reference back to the original caller (`parent`).
4.  **Awaiting Result**: The `await` function is a blocking call that simply enters a `receive` block, waiting for one of three things:
    *   The success message with the result.
    *   A `:DOWN` message indicating the task crashed.
    *   A timeout, after which `await` will kill the task process and return a timeout error.

---

### 4. Workflow Action Architecture

The `Jido.Actions.Workflow` module provides a special type of action that executes a predefined sequence of other actions. This diagram shows its internal control flow.

```mermaid
graph TD
    A["Client calls Jido.Exec.run(MyWorkflow, ...)"] --> B{"MyWorkflow.run"};

    B --> C{"execute_workflow (Enum.reduce_while over steps)"};
    C --> D{"For each step, call execute_step(step, ...)"};
    D --> E{"Step Type?"};

    E -- :step --> F["Execute single instruction execute_instruction"];
    F --> G[Normalize Instruction];
    G --> H["Call Action.run(params, context) for the inner action"];

    E -- :branch --> I["Evaluate branch condition execute_branch"];
    I --> J{"Condition True?"};
    J -- Yes --> K["Recursively call execute_step(true_branch)"];
    J -- No --> L["Recursively call execute_step(false_branch)"];

    E -- :parallel --> M["Execute instructions in parallel execute_parallel (Task.async_stream)"];
    M --> N[Collect results];

    K --> O;
    L --> O;
    H --> O{"Merge result into accumulated state"};
    N --> O;

    O --> C;
    C --> P[Return Final Accumulated Results];
    P --> A;

    %% Elixir-inspired styling
    classDef userLayer fill:#4e2a8e,stroke:#24292e,stroke-width:2px,color:#fff
    classDef coreAbstraction fill:#7c4dbd,stroke:#4e2a8e,stroke-width:2px,color:#fff
    classDef keyModule fill:#9b72d0,stroke:#4e2a8e,stroke-width:2px,color:#fff
    classDef clientLayer fill:#b89ce0,stroke:#4e2a8e,stroke-width:2px,color:#24292e
    classDef serviceLayer fill:#d4c5ec,stroke:#4e2a8e,stroke-width:1px,color:#24292e
    classDef decision fill:#fdfbf7,stroke:#4e2a8e,stroke-width:2px,color:#24292e

    class A userLayer
    class B,C coreAbstraction
    class E,J decision
    class D,F,G,H,I,K,L,M,N,O keyModule
    class P serviceLayer

    %% Darker arrow styling for better visibility
    linkStyle default stroke:#24292e,stroke-width:2px
```

#### **Diagram Explanation:**

A `Workflow` action is itself a standard action, but its `run` logic is a mini-interpreter for a list of steps.

1.  **Entry Point**: Execution starts like any other action via `Jido.Exec.run`.
2.  **`execute_workflow`**: The main loop iterates through the `@workflow_steps` defined in the module. It maintains an accumulator for parameters, which allows the output of one step to be used as input for the next.
3.  **`execute_step`**: This function acts as a dispatcher based on the step type (`:step`, `:branch`, etc.).
4.  **Step Execution**:
    *   **`:step`**: A standard, single action is executed.
    *   **`:branch`**: A condition is evaluated. Based on the result, the workflow recursively executes either the `true_branch` or `false_branch`, which are themselves steps. The condition can be a static value or a dynamic one resolved at runtime by overriding `execute_step`.
    *   **`:parallel`**: Executes multiple instructions concurrently, typically using OTP tasks, and waits for all to complete.
5.  **State Accumulation**: The result of each step is merged back into the `params` map, making it available to subsequent steps in the workflow.

---

### 5. AI Tool Integration Architecture

This diagram explains how a `Jido.Action` can be transformed into a "tool" that a Large Language Model (LLM) can understand and use.

```mermaid
graph TD
    subgraph Elixir Application
        Setup[Agent/Boot Process]
        ToolModule[Jido.Actions.Tool]
        MyAction["MyAction Module (implements Jido.Action)"]
        Exec[Jido.Exec]
    end

    subgraph External AI System
        LLM[Large Language Model]
        AgentRuntime[Agent Runtime]
    end

    Setup -->|"1 to_tool(MyAction)"| ToolModule;
    ToolModule -->|2 Reads metadata| MyAction;
    MyAction -->|"name(), description()"| ToolModule;
    MyAction -->|"schema()"| ToolModule;

    ToolModule -->|3 Converts schema| ToolModule;
    ToolModule -->|4 Returns Tool Definition| Setup;
    Setup -->|5 Provides tools to| AgentRuntime;
    AgentRuntime -->|6 Injects into prompt| LLM;

    LLM -->|"7 Decides to call tool with args (JSON)"| AgentRuntime;
    AgentRuntime -->|"8 Calls tool.function(args)"| ToolModule;

    ToolModule -->|9 Converts string keys to atoms| ToolModule;
    ToolModule -->|"10 Jido.Exec.run(MyAction, ...)"| Exec;

    Exec -->|11 Executes action| MyAction;
    MyAction --> Exec;
    Exec -->|12 Returns result| ToolModule;
    ToolModule -->|13 Encodes result to JSON string| AgentRuntime;
    AgentRuntime -->|14 Provides result to| LLM;

    %% Elixir-inspired styling
    classDef userLayer fill:#4e2a8e,stroke:#24292e,stroke-width:2px,color:#fff
    classDef coreAbstraction fill:#7c4dbd,stroke:#4e2a8e,stroke-width:2px,color:#fff
    classDef keyModule fill:#9b72d0,stroke:#4e2a8e,stroke-width:2px,color:#fff
    classDef clientLayer fill:#b89ce0,stroke:#4e2a8e,stroke-width:2px,color:#24292e
    classDef serviceLayer fill:#d4c5ec,stroke:#4e2a8e,stroke-width:1px,color:#24292e
    classDef externalSystem fill:#f5f5f5,stroke:#666,stroke-width:1px,color:#24292e
    classDef adapter fill:#fdfbf7,stroke:#4e2a8e,stroke-width:2px,color:#24292e

    class Setup userLayer
    class MyAction coreAbstraction
    class Exec,ToolModule keyModule
    class AgentRuntime serviceLayer
    class LLM externalSystem

    %% Darker arrow styling for better visibility
    linkStyle default stroke:#24292e,stroke-width:2px
```

#### **Diagram Explanation:**

1.  **Introspection**: At boot time, the `Jido.Actions.Tool.to_tool/1` function is called on an action module (`MyAction`).
2.  **Metadata Extraction**: `to_tool` reads the action's `name`, `description`, and `schema` using the functions defined by `use Jido.Action`.
3.  **Schema Conversion**: The `schema`, which is a `NimbleOptions` keyword list, is converted into a standard JSON Schema map. This involves mapping Elixir types (`:string`, `:integer`) to JSON Schema types (`"string"`, `"integer"`).
4.  **Tool Definition**: The function returns a map containing the `name`, `description`, and the generated `parameters` schema. This map is the "Tool Definition".
5.  **LLM Integration**: This tool definition is passed to an LLM, usually as part of the system prompt, so the model knows what functions it can call and what arguments they expect.
6.  **Function Calling**: When the LLM decides to use the tool, it generates a JSON object with the function name and arguments.
7.  **Execution**: The agent runtime calls the `function` specified in the tool definition. This function is an alias for `Jido.Actions.Tool.execute_action/3`.
8.  **Invocation**: `execute_action` takes the JSON arguments, converts them back into an Elixir map with atom keys, and uses `Jido.Exec.run` to execute the original `MyAction`.
9.  **Result Formatting**: The result from the action is encoded as a JSON string and returned to the LLM, completing the loop.
