defmodule DurableObject.TestingTest do
  use ExUnit.Case, async: false
  use DurableObject.Testing, repo: DurableObject.TestRepo

  import DurableObject.TestHelpers

  alias DurableObject.TestRepo

  # --- Test Modules ---

  defmodule Counter do
    use DurableObject

    state do
      field(:count, :integer, default: 0)
      field(:name, :string, default: "unnamed")
    end

    handlers do
      handler(:increment)
      handler(:increment_by, args: [:amount])
      handler(:get)
      handler(:set_name, args: [:name])
      handler(:fail)
    end

    def handle_increment(state) do
      new_count = state.count + 1
      {:reply, new_count, %{state | count: new_count}}
    end

    def handle_increment_by(amount, state) when amount > 0 do
      new_count = state.count + amount
      {:reply, new_count, %{state | count: new_count}}
    end

    def handle_increment_by(amount, _state) when amount <= 0 do
      {:error, :invalid_amount}
    end

    def handle_get(state) do
      {:reply, state.count, state}
    end

    def handle_set_name(name, state) do
      {:reply, :ok, %{state | name: name}}
    end

    def handle_fail(_state) do
      {:error, :intentional_failure}
    end
  end

  defmodule AlarmCounter do
    use DurableObject

    state do
      field(:count, :integer, default: 0)
      field(:alarm_fired, :boolean, default: false)
    end

    handlers do
      handler(:increment)
      handler(:get)
      handler(:schedule_reset, args: [:delay_ms])
    end

    def handle_increment(state) do
      {:reply, state.count + 1, %{state | count: state.count + 1}}
    end

    def handle_get(state) do
      {:reply, state, state}
    end

    def handle_schedule_reset(delay_ms, state) do
      {:reply, :ok, state, {:schedule_alarm, :reset, delay_ms}}
    end

    def handle_alarm(:reset, state) do
      {:noreply, %{state | count: 0, alarm_fired: true}}
    end

    def handle_alarm(:recurring, state) do
      new_count = state.count + 1
      {:noreply, %{state | count: new_count}, {:schedule_alarm, :recurring, 1000}}
    end

    def handle_alarm(:chain_a, state) do
      {:noreply, %{state | count: state.count + 10}, {:schedule_alarm, :chain_b, 1000}}
    end

    def handle_alarm(:chain_b, state) do
      {:noreply, %{state | count: state.count + 100}}
    end
  end

  # --- perform_handler/4 Tests ---

  describe "perform_handler/4" do
    test "executes handler with no args" do
      state = %{count: 5, name: "test"}

      assert {:reply, 6, %{count: 6, name: "test"}} =
               perform_handler(Counter, :increment, [], state)
    end

    test "executes handler with args" do
      state = %{count: 0, name: "test"}

      assert {:reply, 10, %{count: 10, name: "test"}} =
               perform_handler(Counter, :increment_by, [10], state)
    end

    test "returns error from handler" do
      state = %{count: 0, name: "test"}

      assert {:error, :invalid_amount} =
               perform_handler(Counter, :increment_by, [-5], state)
    end

    test "returns error for unknown handler" do
      state = %{count: 0}

      assert {:error, {:unknown_handler, :nonexistent}} =
               perform_handler(Counter, :nonexistent, [], state)
    end

    test "handler that returns error tuple" do
      state = %{count: 0, name: "test"}

      assert {:error, :intentional_failure} =
               perform_handler(Counter, :fail, [], state)
    end

    test "handler that schedules alarm" do
      state = %{count: 5, alarm_fired: false}

      assert {:reply, :ok, ^state, {:schedule_alarm, :reset, 1000}} =
               perform_handler(AlarmCounter, :schedule_reset, [1000], state)
    end
  end

  # --- perform_alarm_handler/3 Tests ---

  describe "perform_alarm_handler/3" do
    test "executes alarm handler" do
      state = %{count: 42, alarm_fired: false}

      assert {:noreply, %{count: 0, alarm_fired: true}} =
               perform_alarm_handler(AlarmCounter, :reset, state)
    end

    test "alarm handler that reschedules" do
      state = %{count: 0, alarm_fired: false}

      assert {:noreply, %{count: 1, alarm_fired: false}, {:schedule_alarm, :recurring, 1000}} =
               perform_alarm_handler(AlarmCounter, :recurring, state)
    end

    test "alarm handler that schedules different alarm" do
      state = %{count: 0, alarm_fired: false}

      assert {:noreply, %{count: 10, alarm_fired: false}, {:schedule_alarm, :chain_b, 1000}} =
               perform_alarm_handler(AlarmCounter, :chain_a, state)
    end

    test "returns error if no alarm handler defined" do
      state = %{count: 0}

      assert {:error, :no_alarm_handler} =
               perform_alarm_handler(Counter, :some_alarm, state)
    end
  end

  # --- assert_alarm_scheduled/4 Tests ---

  describe "assert_alarm_scheduled/4" do
    test "passes when alarm is scheduled" do
      id = unique_id("alarm")
      opts = [repo: TestRepo]

      :ok = AlarmCounter.schedule_alarm(id, :reset, 1000, opts)

      assert :ok = assert_alarm_scheduled(AlarmCounter, id, :reset)
    end

    test "fails when alarm is not scheduled" do
      id = unique_id("alarm")

      assert_raise ExUnit.AssertionError, ~r/Expected alarm :reset to be scheduled/, fn ->
        assert_alarm_scheduled(AlarmCounter, id, :reset)
      end
    end

    test "with :within option - passes when alarm within window" do
      id = unique_id("alarm")
      opts = [repo: TestRepo]

      :ok = AlarmCounter.schedule_alarm(id, :reset, 1000, opts)

      assert :ok = assert_alarm_scheduled(AlarmCounter, id, :reset, within: 5000)
    end

    test "with :within option - fails when alarm outside window" do
      id = unique_id("alarm")
      opts = [repo: TestRepo]

      # Schedule alarm 1 hour in the future
      :ok = AlarmCounter.schedule_alarm(id, :reset, :timer.hours(1), opts)

      assert_raise ExUnit.AssertionError, ~r/Expected alarm :reset to be scheduled within/, fn ->
        assert_alarm_scheduled(AlarmCounter, id, :reset, within: 1000)
      end
    end
  end

  # --- refute_alarm_scheduled/4 Tests ---

  describe "refute_alarm_scheduled/4" do
    test "passes when alarm is not scheduled" do
      id = unique_id("alarm")

      assert :ok = refute_alarm_scheduled(AlarmCounter, id, :reset)
    end

    test "fails when alarm is scheduled" do
      id = unique_id("alarm")
      opts = [repo: TestRepo]

      :ok = AlarmCounter.schedule_alarm(id, :reset, 1000, opts)

      assert_raise ExUnit.AssertionError, ~r/Expected no alarm :reset to be scheduled/, fn ->
        refute_alarm_scheduled(AlarmCounter, id, :reset)
      end
    end
  end

  # --- all_scheduled_alarms/3 Tests ---

  describe "all_scheduled_alarms/3" do
    test "returns empty list when no alarms" do
      id = unique_id("alarm")

      assert [] = all_scheduled_alarms(AlarmCounter, id)
    end

    test "returns all alarms sorted by scheduled_at" do
      id = unique_id("alarm")
      opts = [repo: TestRepo]

      # Schedule in reverse order
      :ok = AlarmCounter.schedule_alarm(id, :c, 3000, opts)
      :ok = AlarmCounter.schedule_alarm(id, :a, 1000, opts)
      :ok = AlarmCounter.schedule_alarm(id, :b, 2000, opts)

      alarms = all_scheduled_alarms(AlarmCounter, id)

      assert length(alarms) == 3
      assert Enum.map(alarms, & &1.name) == [:a, :b, :c]
      assert Enum.all?(alarms, &is_struct(&1.scheduled_at, DateTime))
    end
  end

  # --- fire_alarm/4 Tests ---

  describe "fire_alarm/4" do
    test "fires alarm and deletes it" do
      id = unique_id("fire")
      opts = [repo: TestRepo]

      # Start object and schedule alarm
      {:ok, _pid} = DurableObject.ensure_started(AlarmCounter, id, opts)
      {:ok, 1} = AlarmCounter.increment(id, opts)
      :ok = AlarmCounter.schedule_alarm(id, :reset, :timer.hours(1), opts)

      # Verify alarm exists
      assert_alarm_scheduled(AlarmCounter, id, :reset)

      # Fire it
      assert :ok = fire_alarm(AlarmCounter, id, :reset)

      # Alarm should be deleted
      refute_alarm_scheduled(AlarmCounter, id, :reset)

      # Handler should have been called
      {:ok, state} = AlarmCounter.get(id, opts)
      assert state.count == 0
      assert state.alarm_fired == true
    end

    test "raises when alarm doesn't exist" do
      id = unique_id("fire")

      assert_raise ArgumentError, ~r/No alarm :nonexistent scheduled/, fn ->
        fire_alarm(AlarmCounter, id, :nonexistent)
      end
    end

    test "preserves alarm when handler reschedules same alarm" do
      id = unique_id("recurring")
      opts = [repo: TestRepo]

      {:ok, _pid} = DurableObject.ensure_started(AlarmCounter, id, opts)
      :ok = AlarmCounter.schedule_alarm(id, :recurring, 0, opts)

      # Get original scheduled_at
      [original] = all_scheduled_alarms(AlarmCounter, id)

      # Fire alarm - handler reschedules :recurring
      assert :ok = fire_alarm(AlarmCounter, id, :recurring)

      # Alarm should still exist (rescheduled)
      assert_alarm_scheduled(AlarmCounter, id, :recurring)

      # But with a new scheduled_at
      [rescheduled] = all_scheduled_alarms(AlarmCounter, id)
      assert DateTime.compare(rescheduled.scheduled_at, original.scheduled_at) == :gt
    end
  end

  # --- drain_alarms/3 Tests ---

  describe "drain_alarms/3" do
    test "fires all alarms in order and returns count" do
      id = unique_id("drain")
      opts = [repo: TestRepo]

      {:ok, _pid} = DurableObject.ensure_started(AlarmCounter, id, opts)
      :ok = AlarmCounter.schedule_alarm(id, :chain_a, 1000, opts)

      # chain_a fires first, schedules chain_b
      # chain_b fires second
      assert {:ok, 2} = drain_alarms(AlarmCounter, id)

      # No alarms should remain
      assert [] = all_scheduled_alarms(AlarmCounter, id)

      # Both handlers should have run
      {:ok, state} = AlarmCounter.get(id, opts)
      # 10 from chain_a + 100 from chain_b
      assert state.count == 110
    end

    test "returns zero for empty alarm list" do
      id = unique_id("drain")

      assert {:ok, 0} = drain_alarms(AlarmCounter, id)
    end
  end

  # --- assert_persisted/4 Tests ---

  describe "assert_persisted/4" do
    test "passes when object is persisted" do
      id = unique_id("persist")
      opts = [repo: TestRepo]

      {:ok, _pid} = DurableObject.ensure_started(Counter, id, opts)
      {:ok, 5} = Counter.increment_by(id, 5, opts)

      assert :ok = assert_persisted(Counter, id)
    end

    test "fails when object is not persisted" do
      id = unique_id("persist")

      assert_raise ExUnit.AssertionError, ~r/No state found in database/, fn ->
        assert_persisted(Counter, id)
      end
    end

    test "with keyword list assertions - passes when fields match" do
      id = unique_id("persist")
      opts = [repo: TestRepo]

      {:ok, _pid} = DurableObject.ensure_started(Counter, id, opts)
      {:ok, 5} = Counter.increment_by(id, 5, opts)
      {:ok, :ok} = Counter.set_name(id, "test-counter", opts)

      assert :ok = assert_persisted(Counter, id, count: 5, name: "test-counter")
    end

    test "with keyword list assertions - fails when field doesn't match" do
      id = unique_id("persist")
      opts = [repo: TestRepo]

      {:ok, _pid} = DurableObject.ensure_started(Counter, id, opts)
      {:ok, 5} = Counter.increment_by(id, 5, opts)

      assert_raise ExUnit.AssertionError, ~r/Expected persisted state.*to have :count = 10/, fn ->
        assert_persisted(Counter, id, count: 10)
      end
    end

    test "with map assertions" do
      id = unique_id("persist")
      opts = [repo: TestRepo]

      {:ok, _pid} = DurableObject.ensure_started(Counter, id, opts)
      {:ok, 5} = Counter.increment_by(id, 5, opts)

      assert :ok = assert_persisted(Counter, id, %{count: 5})
    end
  end

  # --- get_persisted_state/3 Tests ---

  describe "get_persisted_state/3" do
    test "returns state with atom keys" do
      id = unique_id("get-state")
      opts = [repo: TestRepo]

      {:ok, _pid} = DurableObject.ensure_started(Counter, id, opts)
      {:ok, 5} = Counter.increment_by(id, 5, opts)
      {:ok, :ok} = Counter.set_name(id, "my-counter", opts)

      state = get_persisted_state(Counter, id)

      assert state.count == 5
      assert state.name == "my-counter"
      assert is_atom(hd(Map.keys(state)))
    end

    test "returns nil when not persisted" do
      id = unique_id("get-state")

      assert nil == get_persisted_state(Counter, id)
    end
  end

  # --- assert_eventually/2 Tests ---

  describe "assert_eventually/2" do
    test "passes when condition is immediately true" do
      assert :ok = assert_eventually(fn -> true end)
    end

    test "passes when condition becomes true" do
      counter = :counters.new(1, [])

      # Start a process that will set the counter after 50ms
      spawn(fn ->
        Process.sleep(50)
        :counters.add(counter, 1, 1)
      end)

      assert :ok =
               assert_eventually(
                 fn ->
                   :counters.get(counter, 1) == 1
                 end,
                 timeout: 200
               )
    end

    test "fails when condition never becomes true" do
      assert_raise ExUnit.AssertionError, ~r/Condition did not become true/, fn ->
        assert_eventually(fn -> false end, timeout: 100, interval: 10)
      end
    end

    test "respects custom interval" do
      # Track how many times the condition is checked
      counter = :counters.new(1, [])

      assert_raise ExUnit.AssertionError, fn ->
        assert_eventually(
          fn ->
            :counters.add(counter, 1, 1)
            false
          end,
          timeout: 100,
          interval: 30
        )
      end

      # Should have checked roughly 4 times (100ms / 30ms + initial check)
      # Allow some tolerance for timing
      checks = :counters.get(counter, 1)
      assert checks >= 3 and checks <= 6
    end
  end

  # --- Integration Tests ---

  describe "integration: full lifecycle" do
    test "typical test workflow" do
      id = unique_id("integration")
      opts = [repo: TestRepo]

      # Create and use object
      {:ok, 5} = Counter.increment_by(id, 5, opts)
      {:ok, 8} = Counter.increment_by(id, 3, opts)

      # Verify persisted state
      assert_persisted(Counter, id, count: 8)
    end

    test "alarm workflow" do
      id = unique_id("alarm-integration")
      opts = [repo: TestRepo]

      # Set up object with state (increment 10 times to get count of 10)
      {:ok, _pid} = DurableObject.ensure_started(AlarmCounter, id, opts)

      for _ <- 1..10 do
        {:ok, _} = AlarmCounter.increment(id, opts)
      end

      {:ok, state} = AlarmCounter.get(id, opts)
      assert state.count == 10

      # Schedule an alarm
      :ok = AlarmCounter.schedule_alarm(id, :reset, :timer.hours(1), opts)

      # Verify alarm is scheduled
      assert_alarm_scheduled(AlarmCounter, id, :reset)

      # List all alarms
      alarms = all_scheduled_alarms(AlarmCounter, id)
      assert length(alarms) == 1

      # Fire the alarm (bypassing timing)
      fire_alarm(AlarmCounter, id, :reset)

      # Verify alarm fired and was deleted
      refute_alarm_scheduled(AlarmCounter, id, :reset)
      assert_persisted(AlarmCounter, id, count: 0, alarm_fired: true)
    end
  end

  describe "integration: prefix support" do
    # Skip if not testing multi-tenancy
    @tag :skip
    test "works with table prefix" do
      id = unique_id("prefix")
      prefix = "tenant_test"
      opts = [repo: TestRepo, prefix: prefix]

      # Would need to create the prefixed tables first
      # This test documents the expected behavior
      {:ok, 5} = Counter.increment_by(id, 5, opts)
      assert_persisted(Counter, id, [count: 5], prefix: prefix)
    end
  end
end
