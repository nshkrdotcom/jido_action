# Comprehensive Use Cases and Integration Points for Jido Action Framework

## Core Use Cases

### 1. **Basic Action Composition**
```elixir
# Simple data processing pipeline
[
  ValidateInput,
  {TransformData, %{format: "json"}},
  {SaveToDatabase, %{table: "processed_data"}},
  NotifyCompletion
]
```

**Applications:**
- Data transformation pipelines
- Input validation and sanitization
- Multi-step form processing
- File processing workflows

### 2. **Business Process Automation**
```elixir
# Order processing workflow
[
  {ValidateOrder, %{strict: true}},
  CheckInventory,
  {CalculateShipping, %{method: "express"}},
  ProcessPayment,
  {CreateShipment, %{carrier: "fedex"}},
  SendConfirmationEmail
]
```

**Applications:**
- E-commerce order fulfillment
- Invoice processing
- Customer onboarding flows
- Approval workflows

### 3. **API Orchestration**
```elixir
# Multi-service API calls
[
  {FetchUserProfile, %{user_id: "123"}},
  {EnrichWithPreferences, %{include_history: true}},
  {CallRecommendationService, %{limit: 10}},
  {FormatResponse, %{version: "v2"}}
]
```

**Applications:**
- Microservice orchestration
- Third-party API integration
- Data aggregation from multiple sources
- Service mesh coordination

## Advanced Use Cases

### 4. **Error Recovery and Compensation**
```elixir
defmodule PaymentAction do
  use Jido.Action,
    compensation: [enabled: true, timeout: 5000]

  def run(%{amount: amount, card: card}, _context) do
    # Payment processing logic
    case charge_card(card, amount) do
      {:ok, transaction} -> {:ok, %{transaction_id: transaction.id}}
      error -> {:error, error}
    end
  end

  def on_error(%{amount: amount}, _error, _context, _opts) do
    # Automatic refund on failure
    {:ok, %{refunded: true, amount: amount}}
  end
end
```

**Applications:**
- Financial transaction rollbacks
- Resource cleanup on failure
- Database transaction compensation
- Distributed transaction management

### 5. **Conditional Workflows**
```elixir
# Dynamic workflow based on conditions
defmodule ConditionalWorkflow do
  use Jido.Actions.Workflow,
    steps: [
      {:step, [name: "validate"], [ValidateInput]},
      {:branch, [name: "check_premium"], [
        true,  # Condition evaluated at runtime
        {:step, [name: "premium_flow"], [PremiumProcessing]},
        {:step, [name: "standard_flow"], [StandardProcessing]}
      ]},
      {:step, [name: "finalize"], [FinalizeResult]}
    ]

  def execute_step({:branch, [name: "check_premium"], [_, true_branch, false_branch]}, params, context) do
    if params.user_type == "premium" do
      execute_step(true_branch, params, context)
    else
      execute_step(false_branch, params, context)
    end
  end
end
```

**Applications:**
- User role-based processing
- Feature flag-driven workflows
- A/B testing implementations
- Dynamic business rule execution

### 6. **Parallel Processing**
```elixir
# Concurrent data processing
defmodule ParallelDataProcessor do
  use Jido.Actions.Workflow,
    steps: [
      {:step, [name: "prepare"], [PrepareData]},
      {:parallel, [name: "process"], [
        {ProcessImages, %{quality: "high"}},
        {ExtractMetadata, %{include_exif: true}},
        {GenerateThumbnails, %{sizes: ["small", "medium", "large"]}},
        {VirusScan, %{deep_scan: true}}
      ]},
      {:step, [name: "aggregate"], [AggregateResults]}
    ]
end
```

**Applications:**
- Media processing pipelines
- Batch data analysis
- Parallel API calls
- Independent validation checks

## Integration Points

### 7. **AI/LLM Integration**

#### OpenAI Function Calling
```elixir
# Convert actions to OpenAI tools
defmodule WeatherAction do
  use Jido.Action,
    name: "get_weather",
    description: "Gets current weather for a location",
    schema: [
      location: [type: :string, required: true, doc: "City name"],
      units: [type: {:in, ["celsius", "fahrenheit"]}, default: "celsius"]
    ]
end

# Usage with OpenAI
tools = [WeatherAction.to_tool()]
OpenAI.chat_completion(%{
  model: "gpt-4",
  messages: messages,
  tools: tools
})
```

#### LangChain Integration
```elixir
# Custom LangChain tool wrapper
defmodule JidoLangChainTool do
  def from_action(action_module) do
    tool = action_module.to_tool()
    
    %LangChain.Tool{
      name: tool.name,
      description: tool.description,
      parameters_schema: tool.parameters_schema,
      function: tool.function
    }
  end
end
```

### 8. **Phoenix/Web Framework Integration**

#### Phoenix Controller Actions
```elixir
defmodule MyAppWeb.OrderController do
  use MyAppWeb, :controller

  def create(conn, params) do
    context = %{
      user_id: conn.assigns.current_user.id,
      request_id: get_req_header(conn, "x-request-id")
    }

    case Jido.Exec.run(ProcessOrderAction, params, context) do
      {:ok, result} ->
        json(conn, result)
      {:error, error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: to_string(error)})
    end
  end
end
```

#### Phoenix LiveView Integration
```elixir
defmodule MyAppWeb.OrderLive do
  use MyAppWeb, :live_view

  def handle_event("process_order", params, socket) do
    async_ref = Jido.Exec.run_async(
      ProcessOrderAction,
      params,
      %{user_id: socket.assigns.user_id}
    )

    {:noreply, assign(socket, :processing_ref, async_ref)}
  end

  def handle_info({:action_async_result, ref, result}, socket) do
    if socket.assigns.processing_ref.ref == ref do
      {:noreply, assign(socket, :order_result, result)}
    else
      {:noreply, socket}
    end
  end
end
```

### 9. **GenServer/OTP Integration**

#### GenServer Worker with Actions
```elixir
defmodule OrderProcessor do
  use GenServer

  def handle_call({:process_order, order_data}, _from, state) do
    case Jido.Exec.run(ProcessOrderAction, order_data, %{processor_id: self()}) do
      {:ok, result} ->
        {:reply, {:ok, result}, update_stats(state, :success)}
      {:error, error} ->
        {:reply, {:error, error}, update_stats(state, :error)}
    end
  end

  def handle_cast({:process_order_async, order_data}, state) do
    async_ref = Jido.Exec.run_async(
      ProcessOrderAction,
      order_data,
      %{processor_id: self()}
    )
    
    {:noreply, add_pending_order(state, async_ref)}
  end
end
```

#### Broadway Pipeline Integration
```elixir
defmodule OrderBroadway do
  use Broadway

  def handle_message(_, %Broadway.Message{data: order_data} = message, _) do
    case Jido.Exec.run(ProcessOrderAction, order_data) do
      {:ok, result} ->
        Message.put_data(message, result)
      {:error, error} ->
        Message.failed(message, error)
    end
  end
end
```

### 10. **Database Integration**

#### Ecto Transaction Wrapper
```elixir
defmodule DatabaseAction do
  use Jido.Action,
    name: "database_transaction",
    compensation: [enabled: true]

  def run(%{operations: operations}, context) do
    Repo.transaction(fn ->
      Enum.reduce_while(operations, [], fn op, acc ->
        case execute_operation(op, context) do
          {:ok, result} -> {:cont, [result | acc]}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end)
  end

  def on_error(%{operations: operations}, _error, context, _opts) do
    # Compensation logic for failed database operations
    compensate_operations(operations, context)
  end
end
```

#### Multi-database Operations
```elixir
[
  {WriteToPostgres, %{table: "orders", data: order_data}},
  {WriteToRedis, %{key: "order:#{order_id}", ttl: 3600}},
  {WriteToElasticsearch, %{index: "orders", doc: search_doc}},
  {UpdateAnalytics, %{event: "order_created", properties: analytics_data}}
]
```

### 11. **Message Queue Integration**

#### RabbitMQ/AMQP
```elixir
defmodule QueueAction do
  use Jido.Action,
    name: "publish_message"

  def run(%{queue: queue, message: message}, context) do
    case AMQP.Basic.publish(context.channel, "", queue, message) do
      :ok -> {:ok, %{published: true, queue: queue}}
      error -> {:error, error}
    end
  end
end
```

#### Kafka Integration
```elixir
defmodule KafkaPublisher do
  use Jido.Action,
    name: "kafka_publish"

  def run(%{topic: topic, key: key, value: value}, _context) do
    case KafkaEx.produce(topic, 0, value, key: key) do
      :ok -> {:ok, %{topic: topic, key: key}}
      error -> {:error, error}
    end
  end
end
```

### 12. **External Service Integration**

#### HTTP API Calls
```elixir
defmodule SlackNotification do
  use Jido.Actions.ReqAction,
    name: "slack_notify",
    url: "https://hooks.slack.com/services/...",
    method: :post,
    headers: %{"Content-Type" => "application/json"}

  def transform_result(%{response: %{status: 200}} = result) do
    {:ok, %{notification_sent: true, timestamp: DateTime.utc_now()}}
  end

  def transform_result(%{response: response} = result) do
    {:error, "Slack notification failed: #{response.status}"}
  end
end
```

#### Email Service Integration
```elixir
defmodule EmailAction do
  use Jido.Action,
    name: "send_email"

  def run(%{to: to, subject: subject, body: body}, context) do
    case Swoosh.Mailer.deliver(build_email(to, subject, body), context.mailer) do
      {:ok, _} -> {:ok, %{email_sent: true, recipient: to}}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### 13. **Monitoring and Observability**

#### Telemetry Integration
```elixir
# Attach telemetry handlers
:telemetry.attach_many(
  "jido-action-handlers",
  [
    [:jido, :action, :start],
    [:jido, :action, :complete],
    [:jido, :action, :error]
  ],
  &MyApp.Telemetry.handle_action_event/4,
  %{}
)

defmodule MyApp.Telemetry do
  def handle_action_event([:jido, :action, :start], measurements, metadata, _config) do
    Logger.info("Action started: #{inspect(metadata.action)}")
    :prometheus_counter.inc(:jido_actions_started_total, [metadata.action])
  end

  def handle_action_event([:jido, :action, :complete], measurements, metadata, _config) do
    duration_ms = measurements.duration_us / 1000
    :prometheus_histogram.observe(:jido_action_duration_ms, [metadata.action], duration_ms)
  end
end
```

#### APM Integration (New Relic, DataDog)
```elixir
defmodule APMAction do
  use Jido.Action

  def run(params, context) do
    NewRelic.start_transaction("custom", "jido_action")
    NewRelic.add_attribute("action_name", __MODULE__)
    
    try do
      # Action logic here
      result = perform_action(params, context)
      NewRelic.set_transaction_status(:ok)
      {:ok, result}
    rescue
      error ->
        NewRelic.notice_error(error)
        NewRelic.set_transaction_status(:error)
        {:error, error}
    end
  end
end
```

### 14. **Testing Integration**

#### ExUnit Test Helpers
```elixir
defmodule JidoTestHelpers do
  def assert_action_success(action, params, context \\ %{}) do
    case Jido.Exec.run(action, params, context) do
      {:ok, result} -> result
      {:error, error} -> flunk("Expected action to succeed, got error: #{inspect(error)}")
    end
  end

  def assert_action_error(action, params, expected_type, context \\ %{}) do
    case Jido.Exec.run(action, params, context) do
      {:error, %Jido.Action.Error{type: ^expected_type} = error} -> error
      {:error, error} -> flunk("Expected error type #{expected_type}, got: #{inspect(error)}")
      {:ok, result} -> flunk("Expected action to fail, but it succeeded: #{inspect(result)}")
    end
  end
end
```

#### Property-Based Testing
```elixir
defmodule ActionPropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  property "arithmetic actions are commutative for addition" do
    check all a <- integer(),
              b <- integer() do
      result1 = Jido.Exec.run(Jido.Actions.Arithmetic.Add, %{value: a, amount: b})
      result2 = Jido.Exec.run(Jido.Actions.Arithmetic.Add, %{value: b, amount: a})
      
      assert result1 == result2
    end
  end
end
```

### 15. **Deployment and DevOps Integration**

#### Docker Health Checks
```elixir
defmodule HealthCheckAction do
  use Jido.Action,
    name: "health_check"

  def run(_params, _context) do
    checks = [
      database_check(),
      redis_check(),
      external_api_check()
    ]

    if Enum.all?(checks, & &1.healthy) do
      {:ok, %{status: "healthy", checks: checks}}
    else
      {:error, %{status: "unhealthy", checks: checks}}
    end
  end
end
```

#### Kubernetes Jobs
```elixir
# Kubernetes job runner
defmodule K8sJobAction do
  use Jido.Action,
    name: "run_k8s_job"

  def run(%{job_spec: job_spec}, context) do
    case K8s.Client.create(context.k8s_conn, job_spec) do
      {:ok, job} -> 
        wait_for_completion(job, context.k8s_conn)
      error -> 
        {:error, error}
    end
  end
end
```

### 16. **Event Sourcing Integration**

#### Event Store Actions
```elixir
defmodule EventStoreAction do
  use Jido.Action,
    name: "append_events"

  def run(%{stream_uuid: stream_uuid, events: events}, context) do
    case EventStore.append_to_stream(
      context.event_store,
      stream_uuid,
      :any_version,
      events
    ) do
      :ok -> {:ok, %{events_appended: length(events)}}
      error -> {:error, error}
    end
  end
end
```

### 17. **Machine Learning Pipeline Integration**

#### Model Training Actions
```elixir
defmodule MLTrainingAction do
  use Jido.Action,
    name: "train_model",
    compensation: [enabled: true, timeout: 300_000]  # 5 minute timeout

  def run(%{dataset: dataset, model_config: config}, context) do
    case train_model(dataset, config) do
      {:ok, model} -> 
        save_model(model, context.model_store)
        {:ok, %{model_id: model.id, accuracy: model.accuracy}}
      error -> 
        {:error, error}
    end
  end

  def on_error(%{model_id: model_id}, _error, context, _opts) do
    # Clean up partial model artifacts
    cleanup_model_artifacts(model_id, context.model_store)
    {:ok, %{cleanup_completed: true}}
  end
end
```

These use cases and integration points demonstrate the framework's versatility in handling everything from simple data processing to complex distributed systems, AI integration, and enterprise-grade applications. The consistent interface and robust error handling make it suitable for production environments across various domains.
