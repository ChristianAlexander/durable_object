# Testing Durable Objects

This guide covers testing strategies for DurableObject applications, from fast unit tests to full integration tests.

## Overview

DurableObject provides the `DurableObject.Testing` module with helpers that make it easy to:

- **Unit test** handler logic in isolation (no GenServer, no database)
- **Integration test** the full stack with persistence and alarms
- **Fire alarms** immediately without waiting for scheduler polling
- **Assert on state** both in-memory and persisted

## Quick Start

```elixir
defmodule MyApp.CounterTest do
  use ExUnit.Case
  use DurableObject.Testing, repo: MyApp.Repo

  test "increment and alarm workflow" do
    # Call the object
    {:ok, 5} = Counter.increment("user-123", 5)

    # Assert persisted state
    assert_persisted Counter, "user-123", count: 5

    # Schedule and verify alarm
    :ok = Counter.schedule_alarm("user-123", :reset, 1000)
    assert_alarm_scheduled Counter, "user-123", :reset

    # Fire alarm immediately (bypass scheduler)
    fire_alarm(Counter, "user-123", :reset)

    # Verify effects
    refute_alarm_scheduled Counter, "user-123", :reset
    assert_persisted Counter, "user-123", count: 0
  end
end
```

## Unit Testing

Unit tests call handler functions directly without starting a GenServer or touching the database. They're fast and deterministic.

### Testing Handlers

Use [`perform_handler/4`](`DurableObject.Testing.perform_handler/4`) to test regular handlers:

```elixir
describe "handle_increment/2" do
  test "increments the count" do
    state = %{count: 0, name: "test"}

    assert {:reply, 5, %{count: 5, name: "test"}} =
             perform_handler(Counter, :increment_by, [5], state)
  end

  test "rejects negative amounts" do
    state = %{count: 10, name: "test"}

    assert {:error, :invalid_amount} =
             perform_handler(Counter, :increment_by, [-5], state)
  end

  test "schedules alarm on threshold" do
    state = %{count: 99, name: "test"}

    assert {:reply, 100, new_state, {:schedule_alarm, :notify, 0}} =
             perform_handler(Counter, :increment_by, [1], state)

    assert new_state.count == 100
  end
end
```

The handler is called as `handle_increment_by(5, state)` - args come before state.

### Testing Alarm Handlers

Use [`perform_alarm_handler/3`](`DurableObject.Testing.perform_alarm_handler/3`) to test alarm callbacks:

```elixir
describe "handle_alarm/2" do
  test "reset alarm clears count" do
    state = %{count: 42, notified: false}

    assert {:noreply, %{count: 0, notified: false}} =
             perform_alarm_handler(Counter, :reset, state)
  end

  test "recurring alarm reschedules itself" do
    state = %{count: 0, ticks: 0}

    assert {:noreply, new_state, {:schedule_alarm, :tick, 1000}} =
             perform_alarm_handler(Counter, :tick, state)

    assert new_state.ticks == 1
  end
end
```

## Integration Testing

Integration tests use the full GenServer and database. Use these to verify persistence, alarm scheduling, and object lifecycle.

### Setup

The `use DurableObject.Testing` macro handles Ecto sandbox setup:

```elixir
defmodule MyApp.CounterIntegrationTest do
  use ExUnit.Case
  use DurableObject.Testing, repo: MyApp.Repo

  # Tests automatically get:
  # - Ecto sandbox checkout
  # - Shared sandbox mode for cross-process access
end
```

**Note:** Tests using `DurableObject.Testing` cannot use `async: true` because the sandbox runs in shared mode to allow the DurableObject GenServer (a separate process) to access the same database connection.

### State Assertions

The [`assert_persisted/4`](`DurableObject.Testing.assert_persisted/4`) helper combines existence check and field assertions:

```elixir
# Just check it exists
assert_persisted Counter, id

# Check specific fields (keyword list)
assert_persisted Counter, id, count: 5, name: "test"

# Check specific fields (map)
assert_persisted Counter, id, %{count: 5}
```

For custom assertions, use [`get_persisted_state/3`](`DurableObject.Testing.get_persisted_state/3`):

```elixir
state = get_persisted_state(Counter, id)
assert state.count > 0
assert state.name =~ ~r/test/
```

## Alarm Testing

### Asserting Alarm State

Check if an alarm is scheduled:

```elixir
test "alarm is scheduled" do
  id = "alarm-test"
  :ok = Counter.schedule_alarm(id, :cleanup, :timer.hours(1))

  assert_alarm_scheduled Counter, id, :cleanup
end
```

Check that an alarm is scheduled within a time window:

```elixir
test "alarm is scheduled soon" do
  id = "alarm-test"
  :ok = Counter.schedule_alarm(id, :cleanup, :timer.minutes(5))

  assert_alarm_scheduled Counter, id, :cleanup, within: :timer.hours(1)
end
```

Assert an alarm does NOT exist:

```elixir
test "alarm was cancelled" do
  id = "alarm-test"
  :ok = Counter.schedule_alarm(id, :cleanup, 1000)
  :ok = Counter.cancel_alarm(id, :cleanup)

  refute_alarm_scheduled Counter, id, :cleanup
end
```

List all scheduled alarms:

```elixir
test "multiple alarms scheduled" do
  id = "alarm-test"
  :ok = Counter.schedule_alarm(id, :cleanup, 3000)
  :ok = Counter.schedule_alarm(id, :notify, 1000)
  :ok = Counter.schedule_alarm(id, :expire, 2000)

  alarms = all_scheduled_alarms(Counter, id)

  assert length(alarms) == 3
  # Sorted by scheduled_at (earliest first)
  assert Enum.map(alarms, & &1.name) == [:notify, :expire, :cleanup]
end
```

### Firing Alarms

Use [`fire_alarm/4`](`DurableObject.Testing.fire_alarm/4`) to execute an alarm immediately without waiting for the scheduler:

```elixir
test "firing alarm triggers handler" do
  id = "fire-test"

  # Setup: create object with state and schedule alarm
  {:ok, _} = Counter.increment(id, 10)
  :ok = Counter.schedule_alarm(id, :reset, :timer.hours(1))

  # Fire immediately (don't wait an hour!)
  fire_alarm(Counter, id, :reset)

  # Verify handler ran
  assert_persisted Counter, id, count: 0
  refute_alarm_scheduled Counter, id, :reset
end
```

**Note:** [`fire_alarm/4`](`DurableObject.Testing.fire_alarm/4`) starts the object if it's not running. If your test depends on the object NOT being started, use [`perform_alarm_handler/3`](`DurableObject.Testing.perform_alarm_handler/3`) instead.

### Rescheduling Detection

If your alarm handler reschedules the same alarm, [`fire_alarm/4`](`DurableObject.Testing.fire_alarm/4`) preserves it:

```elixir
test "recurring alarm stays scheduled" do
  id = "recurring-test"
  {:ok, _} = DurableObject.ensure_started(RecurringCounter, id, repo: Repo)
  :ok = RecurringCounter.schedule_alarm(id, :tick, 0)

  # Handler increments count and reschedules :tick
  fire_alarm(RecurringCounter, id, :tick)

  # Alarm still exists (was rescheduled)
  assert_alarm_scheduled RecurringCounter, id, :tick

  # But with a new scheduled_at time
  [alarm] = all_scheduled_alarms(RecurringCounter, id)
  assert DateTime.diff(alarm.scheduled_at, DateTime.utc_now(), :second) > 0
end
```

### Draining Alarm Chains

Use [`drain_alarms/3`](`DurableObject.Testing.drain_alarms/3`) to fire all pending alarms, including any scheduled during execution:

```elixir
test "alarm chain completes" do
  id = "chain-test"
  {:ok, _} = DurableObject.ensure_started(ChainCounter, id, repo: Repo)

  # alarm_a schedules alarm_b, alarm_b schedules alarm_c
  :ok = ChainCounter.schedule_alarm(id, :alarm_a, 0)

  # Fire all alarms in the chain - returns count of alarms fired
  {:ok, 3} = drain_alarms(ChainCounter, id)

  # All handlers ran, no alarms remain
  assert [] = all_scheduled_alarms(ChainCounter, id)
  assert_persisted ChainCounter, id, chain_complete: true
end
```

**Warning:** [`drain_alarms/3`](`DurableObject.Testing.drain_alarms/3`) can hang if alarms reschedule indefinitely. Use the `:max_iterations` option to limit iterations:

```elixir
# Stop after 10 alarms (raises if exceeded)
{:ok, _count} = drain_alarms(Counter, id, max_iterations: 10)
```

## Async Testing

For truly asynchronous scenarios where you can't control timing, use [`assert_eventually/2`](`DurableObject.Testing.assert_eventually/2`):

```elixir
test "object shuts down after timeout" do
  id = "shutdown-test"

  # Start with short shutdown timeout
  {:ok, _} = DurableObject.ensure_started(Counter, id,
    repo: Repo,
    shutdown_after: 50
  )

  # Wait for shutdown
  assert_eventually fn ->
    DurableObject.whereis(Counter, id) == nil
  end, timeout: 200
end
```

**Use sparingly** - prefer deterministic tests with [`fire_alarm/4`](`DurableObject.Testing.fire_alarm/4`) over polling with [`assert_eventually/2`](`DurableObject.Testing.assert_eventually/2`).

## Testing Patterns

### Pattern: Test Handler Logic Separately

```elixir
# Unit tests for logic (fast, no DB)
describe "business logic" do
  test "discount calculation" do
    state = %{items: [...], discount_code: "SAVE20"}

    assert {:reply, total, _new_state} =
             perform_handler(Cart, :calculate_total, [], state)

    assert total == 80.00
  end
end

# Integration tests for persistence (slower, with DB)
describe "persistence" do
  test "cart survives restart" do
    id = "cart-test"
    {:ok, _} = Cart.add_item(id, %{sku: "ABC", qty: 2})

    # Stop and restart
    DurableObject.stop(Cart, id)
    {:ok, _} = Cart.get(id)

    assert_persisted Cart, id, items: [%{"sku" => "ABC", "qty" => 2}]
  end
end
```

### Pattern: Test Alarm Side Effects

```elixir
test "expiration alarm deletes cart" do
  id = "expire-test"

  # Create cart that will expire
  {:ok, _} = Cart.create(id)
  :ok = Cart.schedule_alarm(id, :expire, 0)

  # Fire expiration
  fire_alarm(Cart, id, :expire)

  # Cart should be marked as expired
  assert_persisted Cart, id, status: "expired"
end
```

### Pattern: Test Alarm Chains

```elixir
test "order fulfillment workflow" do
  id = "order-test"

  # Place order - schedules :process alarm
  {:ok, _} = Order.place(id, items: [...])
  assert_alarm_scheduled Order, id, :process

  # Process order - schedules :ship alarm
  fire_alarm(Order, id, :process)
  assert_persisted Order, id, status: "processing"
  assert_alarm_scheduled Order, id, :ship

  # Ship order - schedules :deliver alarm
  fire_alarm(Order, id, :ship)
  assert_persisted Order, id, status: "shipped"
  assert_alarm_scheduled Order, id, :deliver

  # Deliver order - complete
  fire_alarm(Order, id, :deliver)
  assert_persisted Order, id, status: "delivered"
  refute_alarm_scheduled Order, id, :deliver
end
```

## Limitations

1. **No async tests**: Tests must use `async: false` (or omit the option) because the Ecto sandbox runs in shared mode for cross-process database access.

2. **fire_alarm starts objects**: [`fire_alarm/4`](`DurableObject.Testing.fire_alarm/4`) will start the DurableObject if it's not running. Use [`perform_alarm_handler/3`](`DurableObject.Testing.perform_alarm_handler/3`) if you need to test alarm logic without starting the object.

3. **Process dictionary**: Helper functions use the process dictionary set by `__setup__/2`, so they only work in the test process itself.

## Reference

See `DurableObject.Testing` for the full API documentation.
