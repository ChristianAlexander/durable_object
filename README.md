# DurableObject

Durable Objects for Elixir - persistent, single-instance objects accessed by ID.

This library provides a programming model for stateful, persistent actors in Elixir, leveraging native GenServer capabilities, Ecto for persistence, and the Spark DSL for a declarative developer experience.

## Features

- **Global Uniqueness**: One instance per (module, object_id) pair across the cluster
- **Persistent State**: State survives process crashes and restarts via Ecto
- **Automatic Lifecycle**: Processes hibernate after inactivity, optionally shut down
- **Alarm Scheduling**: Built-in support for future work with database-backed persistence
- **Declarative DSL**: Define objects with Spark DSL for clean, expressive code
- **Distribution Ready**: Optional Horde integration for multi-node clusters

## Installation

Add `durable_object` to your dependencies:

```elixir
def deps do
  [
    {:durable_object, "~> 0.1.0"},
    # Optional: for distributed mode
    {:horde, "~> 0.9"},
    # Optional: for Oban-based alarm scheduling
    {:oban, "~> 2.17"}
  ]
end
```

### Quick Setup with Igniter

```bash
mix igniter.install durable_object
```

### Manual Setup

1. Generate the migration:

```bash
mix ecto.gen.migration add_durable_objects
```

2. Update the migration file:

```elixir
defmodule MyApp.Repo.Migrations.AddDurableObjects do
  use Ecto.Migration

  def up, do: DurableObject.Migration.up(version: 1)
  def down, do: DurableObject.Migration.down(version: 1)
end
```

3. Run the migration:

```bash
mix ecto.migrate
```

4. Configure DurableObject in your application:

```elixir
# config/config.exs
config :durable_object,
  repo: MyApp.Repo,
  cluster: :local,  # or :horde for distributed
  scheduler: DurableObject.Scheduler.Polling,
  scheduler_opts: [polling_interval: :timer.seconds(30)]
```

## Usage

### Define a Durable Object

```elixir
defmodule MyApp.Counter do
  use DurableObject

  state do
    field :count, :integer, default: 0
    field :last_incremented_at, :utc_datetime
  end

  handlers do
    handler :increment, args: [:amount]
    handler :get
    handler :reset
  end

  options do
    hibernate_after :timer.minutes(5)
    shutdown_after :timer.hours(1)
  end

  def handle_increment(amount \\ 1, state) do
    new_count = Map.get(state, :count, 0) + amount
    new_state = %{state | count: new_count, last_incremented_at: DateTime.utc_now()}
    {:reply, new_count, new_state}
  end

  def handle_get(state) do
    {:reply, Map.get(state, :count, 0), state}
  end

  def handle_reset(state) do
    {:reply, :ok, %{state | count: 0}}
  end
end
```

### Use the Generated Client API

The DSL automatically generates client functions:

```elixir
# Increment by 5
{:ok, 5} = MyApp.Counter.increment("user-123", 5)

# Get current count
{:ok, 5} = MyApp.Counter.get("user-123")

# Reset
{:ok, :ok} = MyApp.Counter.reset("user-123")
```

### Or Use the Generic API

```elixir
{:ok, 5} = DurableObject.call(MyApp.Counter, "user-123", :increment, [5])
{:ok, 5} = DurableObject.call(MyApp.Counter, "user-123", :get)
```

## Alarms

Schedule work to happen in the future:

```elixir
defmodule MyApp.RateLimiter do
  use DurableObject

  state do
    field :requests, :integer, default: 0
    field :window_start, :utc_datetime
  end

  handlers do
    handler :check, args: [:limit]
  end

  def handle_check(limit, state) do
    if state.requests < limit do
      {:reply, :allowed, %{state | requests: state.requests + 1}}
    else
      {:reply, :rate_limited, state}
    end
  end

  @impl DurableObject.Behaviour
  def handle_alarm(:reset_window, state) do
    # Reset the window and reschedule
    {:noreply, %{state | requests: 0, window_start: DateTime.utc_now()},
     {:schedule_alarm, :reset_window, :timer.minutes(1)}}
  end
end
```

## Distribution with Horde

For multi-node clusters, enable Horde:

```elixir
# config/config.exs
config :durable_object,
  cluster: :horde
```

This ensures:
- Only one instance of each object exists across the cluster
- Objects are automatically migrated when nodes join/leave
- Alarms fire exactly once (singleton poller)

## Telemetry

DurableObject emits telemetry events for observability:

- `[:durable_object, :storage, :save, :start | :stop | :exception]`
- `[:durable_object, :storage, :load, :start | :stop | :exception]`
- `[:durable_object, :storage, :release_lock, :start | :stop | :exception]`

## License

MIT License - see [LICENSE](LICENSE) for details.
