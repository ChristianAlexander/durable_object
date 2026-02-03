# DurableObject Usage Rules

> Guidelines for LLM agents assisting with DurableObject, an Elixir library for persistent, single-instance actors.

## Core Concepts

DurableObject provides persistent stateful actors backed by Ecto. Each object is identified by `(module, object_id)` and has:
- Automatic state persistence to database as JSON
- Lifecycle management (hibernate after inactivity, optional shutdown)
- Built-in alarm scheduling
- Optional distributed mode via Horde

## Defining Objects

Use the Spark DSL:

```elixir
defmodule MyApp.Counter do
  use DurableObject

  state do
    field :count, :integer, default: 0
  end

  handlers do
    handler :increment, args: [:amount]
    handler :get
  end

  options do
    hibernate_after :timer.minutes(5)
    shutdown_after :timer.hours(1)
  end

  # Handler arity = args.length + 1 (for state)
  def handle_increment(amount, state) do
    {:reply, state.count + amount, %{state | count: state.count + amount}}
  end

  def handle_get(state) do
    {:reply, state.count, state}
  end
end
```

## Handler Return Values

**Only these return formats are valid:**

```elixir
{:reply, result, new_state}
{:reply, result, new_state, {:schedule_alarm, alarm_name, delay_ms}}
{:noreply, new_state}
{:noreply, new_state, {:schedule_alarm, alarm_name, delay_ms}}
{:error, reason}
```

## Generated Client API

The DSL generates client functions. **Do not call GenServer directly:**

```elixir
# Correct - use generated functions
{:ok, 5} = MyApp.Counter.increment("user-123", 5)
{:ok, count} = MyApp.Counter.get("user-123")

# Also correct - use DurableObject.call
{:ok, 5} = DurableObject.call(MyApp.Counter, "user-123", :increment, [5])
```

## Critical Rules

1. **Handler arity must match**: `handle_<name>/N` where N = length(args) + 1. Mismatch causes `{:error, {:unknown_handler, name}}`.

2. **State is transactional**: Persistence only happens if state changed AND write succeeds. Failed writes rollback in-memory state.

3. **Alarms upsert, not append**: Scheduling an alarm with the same name replaces the existing one.

4. **No repo = no persistence**: Without `:repo` configured, objects are in-memory only. Alarms require both repo and scheduler.

5. **Prefix consistency**: When using multi-tenant prefixes, use the same prefix in all calls and configuration.

## Optional Callbacks

```elixir
# Called once after state loads from database
def after_load(state) do
  {:ok, state}
end

# Called when scheduled alarm fires
def handle_alarm(:cleanup, state) do
  {:noreply, state}
end
```

## Alarm Scheduling

```elixir
:ok = MyApp.Counter.schedule_alarm("user-123", :cleanup, :timer.hours(1))
:ok = MyApp.Counter.cancel_alarm("user-123", :cleanup)
{:ok, alarms} = MyApp.Counter.list_alarms("user-123")
```

## Configuration

### Polling Scheduler (default)

```elixir
config :durable_object,
  repo: MyApp.Repo,
  registry_mode: :local,  # or :horde
  object_keys: :strings,  # :strings | :atoms! | :atoms — map key conversion on load
  scheduler: DurableObject.Scheduler.Polling,
  scheduler_opts: [
    polling_interval: :timer.seconds(30),
    claim_ttl: :timer.seconds(60)
  ]
```

**Polling scheduler notes:**
- `claim_ttl` controls how long a claimed alarm waits before being retried (default: 60s)
- Alarms are claimed before firing and only deleted on success
- Failed handlers will retry after the claim TTL expires
- Uses at-least-once semantics; handlers should be idempotent

### Oban Scheduler

For applications already using Oban. Provides retries, observability, and leverages existing Oban infrastructure.

```elixir
# config/config.exs
config :durable_object,
  repo: MyApp.Repo,
  scheduler: DurableObject.Scheduler.Oban,
  scheduler_opts: [oban_queue: :durable_object_alarms]

# Add the queue to your Oban configuration
config :my_app, Oban,
  repo: MyApp.Repo,
  queues: [durable_object_alarms: 5]
```

If your app uses a custom Oban instance name (e.g., `MyApp.Oban` instead of the default `Oban`), specify it:

```elixir
scheduler_opts: [oban_instance: MyApp.Oban, oban_queue: :durable_object_alarms]
```

**Oban scheduler notes:**
- Alarms scheduled as Oban jobs with `schedule_in`
- Failed alarms retry up to 3 times (Oban's retry policy)
- No additional supervision children - Oban manages everything
- Requires Oban as a dependency (optional dep, must be added explicitly)

## Setup

```bash
mix igniter.install durable_object
```

Or manually run migration:

```elixir
# In a migration file
use DurableObject.Migration, version: 2
```

## Common Mistakes to Avoid

- **Don't use `GenServer.call` directly** - use generated client functions or `DurableObject.call/4`
- **Don't assume alarms fire exactly once** - design handlers to be idempotent
- **Don't forget to configure repo** if you need persistence
- **Don't mix prefixes** across calls to the same logical object
- **Don't return bare values from handlers** - always use the tuple format

## Telemetry

DurableObject emits telemetry events for storage operations:

```
[:durable_object, :storage, :save, :start | :stop | :exception]
[:durable_object, :storage, :load, :start | :stop | :exception]
[:durable_object, :storage, :delete, :start | :stop | :exception]
```

**Measurements:**
- `:start` events: `%{system_time: ...}`
- `:stop` events: `%{duration: ...}` (in native time units)
- `:exception` events: `%{duration: ...}` plus `:kind`, `:reason`, `:stacktrace` in metadata

**Metadata (all events):** `object_type`, `object_id`, `repo`

**Example handler attachment:**

```elixir
:telemetry.attach_many(
  "durable-object-metrics",
  [
    [:durable_object, :storage, :save, :stop],
    [:durable_object, :storage, :load, :stop]
  ],
  &MyApp.Metrics.handle_event/4,
  nil
)
```

## Schema Evolution

New fields with defaults are safe to add. Loaded state merges with defaults, so existing objects get new field defaults automatically.
