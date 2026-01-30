defmodule DurableObject.SchedulerTest do
  use ExUnit.Case, async: false

  alias DurableObject.Scheduler.Polling
  alias DurableObject.Storage.Schemas.Alarm
  alias DurableObject.TestRepo

  import Ecto.Query
  import ExUnit.CaptureLog
  import DurableObject.TestHelpers

  @moduletag :scheduler

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)
    Ecto.Adapters.SQL.Sandbox.mode(TestRepo, {:shared, self()})
    :ok
  end

  # --- Test Modules ---

  defmodule AlarmCounter do
    use DurableObject

    state do
      field(:count, :integer, default: 0)
      field(:alarm_count, :integer, default: 0)
      field(:recurring_count, :integer, default: 0)
      field(:alarm_history, :list, default: [])
    end

    handlers do
      handler(:increment)
      handler(:get)
      handler(:get_alarm_count)
      handler(:get_recurring_count)
      handler(:get_alarm_history)
    end

    def handle_increment(state) do
      {:reply, state.count + 1, %{state | count: state.count + 1}}
    end

    def handle_get(state) do
      {:reply, state.count, state}
    end

    def handle_get_alarm_count(state) do
      {:reply, state.alarm_count, state}
    end

    def handle_get_recurring_count(state) do
      {:reply, state.recurring_count, state}
    end

    def handle_get_alarm_history(state) do
      {:reply, state.alarm_history, state}
    end

    def handle_alarm(:test_alarm, state) do
      entry = %{alarm: "test_alarm", fired_at: DateTime.to_iso8601(DateTime.utc_now())}
      history = [entry | state.alarm_history]
      {:noreply, %{state | alarm_count: state.alarm_count + 1, alarm_history: history}}
    end

    def handle_alarm(:recurring_alarm, state) do
      new_count = state.recurring_count + 1
      entry = %{alarm: "recurring_alarm", fired_at: DateTime.to_iso8601(DateTime.utc_now())}
      history = [entry | state.alarm_history]
      new_state = %{state | recurring_count: new_count, alarm_history: history}
      # Schedule another alarm in 50ms
      {:noreply, new_state, {:schedule_alarm, :recurring_alarm, 50}}
    end

    def handle_alarm(:chain_alarm_a, state) do
      entry = %{alarm: "chain_alarm_a", fired_at: DateTime.to_iso8601(DateTime.utc_now())}
      history = [entry | state.alarm_history]
      new_state = %{state | alarm_history: history}
      # Schedule a different alarm
      {:noreply, new_state, {:schedule_alarm, :chain_alarm_b, 50}}
    end

    def handle_alarm(:chain_alarm_b, state) do
      entry = %{alarm: "chain_alarm_b", fired_at: DateTime.to_iso8601(DateTime.utc_now())}
      history = [entry | state.alarm_history]
      {:noreply, %{state | alarm_history: history}}
    end

    def handle_alarm(:noop_alarm, state) do
      {:noreply, state}
    end

    def handle_alarm(:failing_alarm, _state) do
      raise "simulated handler failure"
    end
  end

  # --- Polling.schedule/4 Tests ---

  describe "Polling.schedule/4" do
    test "schedules an alarm in the database" do
      id = unique_id("sched")
      opts = [repo: TestRepo]

      :ok = Polling.schedule({AlarmCounter, id}, :my_alarm, 1000, opts)

      alarms = TestRepo.all(from(a in Alarm, where: a.object_id == ^id))

      assert length(alarms) == 1
      [alarm] = alarms
      assert alarm.object_type == "Elixir.DurableObject.SchedulerTest.AlarmCounter"
      assert alarm.alarm_name == "my_alarm"
      assert DateTime.diff(alarm.scheduled_at, DateTime.utc_now(), :millisecond) >= 900
    end

    test "replaces existing alarm with same name (upsert)" do
      id = unique_id("sched")
      opts = [repo: TestRepo]

      :ok = Polling.schedule({AlarmCounter, id}, :my_alarm, 5000, opts)
      :ok = Polling.schedule({AlarmCounter, id}, :my_alarm, 1000, opts)

      alarms = TestRepo.all(from(a in Alarm, where: a.object_id == ^id))

      assert length(alarms) == 1
      [alarm] = alarms
      assert DateTime.diff(alarm.scheduled_at, DateTime.utc_now(), :millisecond) < 2000
    end

    test "allows multiple different alarms for same object" do
      id = unique_id("sched")
      opts = [repo: TestRepo]

      :ok = Polling.schedule({AlarmCounter, id}, :alarm_a, 1000, opts)
      :ok = Polling.schedule({AlarmCounter, id}, :alarm_b, 2000, opts)

      alarms = TestRepo.all(from(a in Alarm, where: a.object_id == ^id, order_by: a.alarm_name))

      assert length(alarms) == 2
      assert Enum.map(alarms, & &1.alarm_name) == ["alarm_a", "alarm_b"]
    end

    test "schedules alarm with zero delay" do
      id = unique_id("sched")
      opts = [repo: TestRepo]

      :ok = Polling.schedule({AlarmCounter, id}, :immediate, 0, opts)

      alarms = TestRepo.all(from(a in Alarm, where: a.object_id == ^id))
      assert length(alarms) == 1
      [alarm] = alarms
      assert DateTime.diff(DateTime.utc_now(), alarm.scheduled_at, :second) >= 0
    end

    test "schedules alarm with large delay" do
      id = unique_id("sched")
      opts = [repo: TestRepo]

      one_year_ms = 365 * 24 * 60 * 60 * 1000
      :ok = Polling.schedule({AlarmCounter, id}, :far_future, one_year_ms, opts)

      alarms = TestRepo.all(from(a in Alarm, where: a.object_id == ^id))
      assert length(alarms) == 1
      [alarm] = alarms
      assert DateTime.diff(alarm.scheduled_at, DateTime.utc_now(), :day) >= 364
    end
  end

  # --- Polling.cancel/4 Tests ---

  describe "Polling.cancel/4" do
    test "cancels a scheduled alarm" do
      id = unique_id("cancel")
      opts = [repo: TestRepo]

      :ok = Polling.schedule({AlarmCounter, id}, :my_alarm, 1000, opts)
      :ok = Polling.cancel({AlarmCounter, id}, :my_alarm, opts)

      alarms = TestRepo.all(from(a in Alarm, where: a.object_id == ^id))
      assert alarms == []
    end

    test "returns :ok even if alarm doesn't exist" do
      opts = [repo: TestRepo]
      assert :ok = Polling.cancel({AlarmCounter, unique_id("cancel")}, :no_alarm, opts)
    end

    test "only cancels the specified alarm" do
      id = unique_id("cancel")
      opts = [repo: TestRepo]

      :ok = Polling.schedule({AlarmCounter, id}, :alarm_a, 1000, opts)
      :ok = Polling.schedule({AlarmCounter, id}, :alarm_b, 2000, opts)
      :ok = Polling.cancel({AlarmCounter, id}, :alarm_a, opts)

      alarms = TestRepo.all(from(a in Alarm, where: a.object_id == ^id))
      assert length(alarms) == 1
      assert hd(alarms).alarm_name == "alarm_b"
    end
  end

  # --- Polling.cancel_all/3 Tests ---

  describe "Polling.cancel_all/3" do
    test "cancels all alarms for an object" do
      id = unique_id("cancel-all")
      opts = [repo: TestRepo]

      :ok = Polling.schedule({AlarmCounter, id}, :alarm_a, 1000, opts)
      :ok = Polling.schedule({AlarmCounter, id}, :alarm_b, 2000, opts)
      :ok = Polling.schedule({AlarmCounter, id}, :alarm_c, 3000, opts)
      :ok = Polling.cancel_all({AlarmCounter, id}, opts)

      alarms = TestRepo.all(from(a in Alarm, where: a.object_id == ^id))
      assert alarms == []
    end

    test "does not cancel alarms for other objects" do
      id1 = unique_id("cancel-all")
      id2 = unique_id("cancel-all")
      opts = [repo: TestRepo]

      :ok = Polling.schedule({AlarmCounter, id1}, :alarm_a, 1000, opts)
      :ok = Polling.schedule({AlarmCounter, id2}, :alarm_b, 2000, opts)
      :ok = Polling.cancel_all({AlarmCounter, id1}, opts)

      alarms1 = TestRepo.all(from(a in Alarm, where: a.object_id == ^id1))
      alarms2 = TestRepo.all(from(a in Alarm, where: a.object_id == ^id2))

      assert alarms1 == []
      assert length(alarms2) == 1
    end

    test "returns :ok when no alarms exist" do
      opts = [repo: TestRepo]
      assert :ok = Polling.cancel_all({AlarmCounter, unique_id("cancel-all")}, opts)
    end
  end

  # --- Polling.list/3 Tests ---

  describe "Polling.list/3" do
    test "lists all alarms for an object ordered by scheduled time" do
      id = unique_id("list")
      opts = [repo: TestRepo]

      :ok = Polling.schedule({AlarmCounter, id}, :alarm_b, 2000, opts)
      :ok = Polling.schedule({AlarmCounter, id}, :alarm_a, 1000, opts)
      :ok = Polling.schedule({AlarmCounter, id}, :alarm_c, 3000, opts)

      {:ok, alarms} = Polling.list({AlarmCounter, id}, opts)

      assert length(alarms) == 3
      assert Enum.map(alarms, &elem(&1, 0)) == [:alarm_a, :alarm_b, :alarm_c]
    end

    test "returns empty list when no alarms exist" do
      opts = [repo: TestRepo]
      {:ok, alarms} = Polling.list({AlarmCounter, unique_id("list")}, opts)
      assert alarms == []
    end

    test "returns atoms for alarm names" do
      id = unique_id("list")
      opts = [repo: TestRepo]

      :ok = Polling.schedule({AlarmCounter, id}, :my_alarm, 1000, opts)

      {:ok, [{alarm_name, _scheduled_at}]} = Polling.list({AlarmCounter, id}, opts)
      assert is_atom(alarm_name)
      assert alarm_name == :my_alarm
    end

    test "returns DateTime for scheduled_at" do
      id = unique_id("list")
      opts = [repo: TestRepo]

      :ok = Polling.schedule({AlarmCounter, id}, :my_alarm, 1000, opts)

      {:ok, [{_alarm_name, scheduled_at}]} = Polling.list({AlarmCounter, id}, opts)
      assert %DateTime{} = scheduled_at
    end
  end

  # --- Poller Integration Tests ---

  describe "Poller" do
    test "fires overdue alarms" do
      id = unique_id("poll")
      opts = [repo: TestRepo]

      {:ok, poller} = start_test_poller()
      {:ok, _pid} = DurableObject.ensure_started(AlarmCounter, id, opts)

      # Schedule an alarm that's already overdue
      :ok = Polling.schedule({AlarmCounter, id}, :test_alarm, 0, opts)

      # Trigger the poller
      send(poller, :check_alarms)
      Process.sleep(100)

      # Alarm should be fired and deleted
      {:ok, alarms} = Polling.list({AlarmCounter, id}, opts)
      assert alarms == []

      # Handler should have been called
      {:ok, count} = AlarmCounter.get_alarm_count(id, opts)
      assert count == 1

      GenServer.stop(poller)
    end

    test "alarm handler can schedule a new alarm with the same name (recurring)" do
      id = unique_id("recurring")
      opts = [repo: TestRepo]

      {:ok, poller} = start_test_poller()
      {:ok, _pid} = DurableObject.ensure_started(AlarmCounter, id, opts)

      # Schedule the initial recurring alarm
      :ok = Polling.schedule({AlarmCounter, id}, :recurring_alarm, 0, opts)

      # Fire it once
      send(poller, :check_alarms)
      Process.sleep(100)

      # The handler should have scheduled a new alarm
      {:ok, alarms} = Polling.list({AlarmCounter, id}, opts)
      assert length(alarms) == 1
      assert hd(alarms) |> elem(0) == :recurring_alarm

      # Handler should have been called once
      {:ok, count} = AlarmCounter.get_recurring_count(id, opts)
      assert count == 1

      # Wait for the rescheduled alarm to become due
      Process.sleep(100)

      # Fire again
      send(poller, :check_alarms)
      Process.sleep(100)

      # Handler should have been called twice
      {:ok, count} = AlarmCounter.get_recurring_count(id, opts)
      assert count == 2

      # And another alarm should be scheduled
      {:ok, alarms} = Polling.list({AlarmCounter, id}, opts)
      assert length(alarms) == 1

      GenServer.stop(poller)
    end

    test "alarm handler can schedule a different alarm (chaining)" do
      id = unique_id("chain")
      opts = [repo: TestRepo]

      {:ok, poller} = start_test_poller()
      {:ok, _pid} = DurableObject.ensure_started(AlarmCounter, id, opts)

      # Schedule chain_alarm_a which will schedule chain_alarm_b
      :ok = Polling.schedule({AlarmCounter, id}, :chain_alarm_a, 0, opts)

      # Fire first alarm
      send(poller, :check_alarms)
      Process.sleep(100)

      # chain_alarm_b should now be scheduled
      {:ok, alarms} = Polling.list({AlarmCounter, id}, opts)
      assert length(alarms) == 1
      assert hd(alarms) |> elem(0) == :chain_alarm_b

      # Wait and fire second alarm
      Process.sleep(100)
      send(poller, :check_alarms)
      Process.sleep(100)

      # Both alarms should have fired
      {:ok, history} = AlarmCounter.get_alarm_history(id, opts)
      alarm_names = Enum.map(history, & &1.alarm)
      assert "chain_alarm_a" in alarm_names
      assert "chain_alarm_b" in alarm_names

      # No more alarms scheduled
      {:ok, alarms} = Polling.list({AlarmCounter, id}, opts)
      assert alarms == []

      GenServer.stop(poller)
    end

    test "multiple overdue alarms are all fired" do
      id = unique_id("multi")
      opts = [repo: TestRepo]

      {:ok, poller} = start_test_poller()
      {:ok, _pid} = DurableObject.ensure_started(AlarmCounter, id, opts)

      # Schedule multiple overdue alarms
      :ok = Polling.schedule({AlarmCounter, id}, :test_alarm, 0, opts)
      # Use noop_alarm for a second one since test_alarm would conflict
      :ok = Polling.schedule({AlarmCounter, id}, :noop_alarm, 0, opts)

      send(poller, :check_alarms)
      Process.sleep(100)

      {:ok, alarms} = Polling.list({AlarmCounter, id}, opts)
      assert alarms == []

      GenServer.stop(poller)
    end
  end

  # --- DurableObject API Tests ---

  describe "DurableObject.schedule_alarm/5" do
    test "schedules an alarm via the public API" do
      id = unique_id("api")
      opts = [repo: TestRepo]

      :ok = DurableObject.schedule_alarm(AlarmCounter, id, :my_alarm, 1000, opts)

      {:ok, alarms} = Polling.list({AlarmCounter, id}, opts)
      assert length(alarms) == 1
      assert hd(alarms) |> elem(0) == :my_alarm
    end

    test "uses default repo from config" do
      id = unique_id("api")

      # Temporarily set default repo
      Application.put_env(:durable_object, :repo, TestRepo)

      try do
        :ok = DurableObject.schedule_alarm(AlarmCounter, id, :my_alarm, 1000)

        {:ok, alarms} = Polling.list({AlarmCounter, id}, repo: TestRepo)
        assert length(alarms) == 1
      after
        Application.delete_env(:durable_object, :repo)
      end
    end
  end

  describe "DurableObject.cancel_alarm/4" do
    test "cancels an alarm via the public API" do
      id = unique_id("api")
      opts = [repo: TestRepo]

      :ok = DurableObject.schedule_alarm(AlarmCounter, id, :my_alarm, 1000, opts)
      :ok = DurableObject.cancel_alarm(AlarmCounter, id, :my_alarm, opts)

      {:ok, alarms} = Polling.list({AlarmCounter, id}, opts)
      assert alarms == []
    end
  end

  describe "DurableObject.cancel_all_alarms/3" do
    test "cancels all alarms via the public API" do
      id = unique_id("api")
      opts = [repo: TestRepo]

      :ok = DurableObject.schedule_alarm(AlarmCounter, id, :alarm_a, 1000, opts)
      :ok = DurableObject.schedule_alarm(AlarmCounter, id, :alarm_b, 2000, opts)
      :ok = DurableObject.cancel_all_alarms(AlarmCounter, id, opts)

      {:ok, alarms} = Polling.list({AlarmCounter, id}, opts)
      assert alarms == []
    end
  end

  describe "DurableObject.list_alarms/3" do
    test "lists alarms via the public API" do
      id = unique_id("api")
      opts = [repo: TestRepo]

      :ok = DurableObject.schedule_alarm(AlarmCounter, id, :alarm_a, 1000, opts)
      :ok = DurableObject.schedule_alarm(AlarmCounter, id, :alarm_b, 2000, opts)

      {:ok, alarms} = DurableObject.list_alarms(AlarmCounter, id, opts)
      assert length(alarms) == 2
    end
  end

  # --- Module-level API Tests ---

  describe "Module.schedule_alarm/4" do
    test "schedules an alarm via the module API" do
      id = unique_id("module")
      opts = [repo: TestRepo]

      :ok = AlarmCounter.schedule_alarm(id, :my_alarm, 1000, opts)

      {:ok, alarms} = AlarmCounter.list_alarms(id, opts)
      assert length(alarms) == 1
      assert hd(alarms) |> elem(0) == :my_alarm
    end
  end

  describe "Module.cancel_alarm/3" do
    test "cancels an alarm via the module API" do
      id = unique_id("module")
      opts = [repo: TestRepo]

      :ok = AlarmCounter.schedule_alarm(id, :my_alarm, 1000, opts)
      :ok = AlarmCounter.cancel_alarm(id, :my_alarm, opts)

      {:ok, alarms} = AlarmCounter.list_alarms(id, opts)
      assert alarms == []
    end
  end

  describe "Module.cancel_all_alarms/2" do
    test "cancels all alarms via the module API" do
      id = unique_id("module")
      opts = [repo: TestRepo]

      :ok = AlarmCounter.schedule_alarm(id, :alarm_a, 1000, opts)
      :ok = AlarmCounter.schedule_alarm(id, :alarm_b, 2000, opts)
      :ok = AlarmCounter.cancel_all_alarms(id, opts)

      {:ok, alarms} = AlarmCounter.list_alarms(id, opts)
      assert alarms == []
    end
  end

  describe "Module.list_alarms/2" do
    test "lists alarms via the module API" do
      id = unique_id("module")
      opts = [repo: TestRepo]

      :ok = AlarmCounter.schedule_alarm(id, :alarm_a, 1000, opts)
      :ok = AlarmCounter.schedule_alarm(id, :alarm_b, 2000, opts)

      {:ok, alarms} = AlarmCounter.list_alarms(id, opts)
      assert length(alarms) == 2
      assert Enum.map(alarms, &elem(&1, 0)) == [:alarm_a, :alarm_b]
    end
  end

  # --- Edge Cases ---

  describe "edge cases" do
    test "scheduling alarm from outside object doesn't require object to be running" do
      id = unique_id("edge")
      opts = [repo: TestRepo]

      # Object is not started
      assert DurableObject.whereis(AlarmCounter, id) == nil

      # But we can still schedule an alarm
      :ok = AlarmCounter.schedule_alarm(id, :my_alarm, 1000, opts)

      {:ok, alarms} = AlarmCounter.list_alarms(id, opts)
      assert length(alarms) == 1
    end

    test "alarm names with special characters" do
      id = unique_id("edge")
      opts = [repo: TestRepo]

      :ok = Polling.schedule({AlarmCounter, id}, :alarm_with_underscore, 1000, opts)
      :ok = Polling.schedule({AlarmCounter, id}, :AlarmWithCaps, 2000, opts)

      {:ok, alarms} = Polling.list({AlarmCounter, id}, opts)
      assert length(alarms) == 2
    end

    test "object_id with special characters" do
      id = "user:123:session:abc-def"
      opts = [repo: TestRepo]

      :ok = Polling.schedule({AlarmCounter, id}, :my_alarm, 1000, opts)

      {:ok, alarms} = Polling.list({AlarmCounter, id}, opts)
      assert length(alarms) == 1
    end

    test "very short delay (1ms)" do
      id = unique_id("edge")
      opts = [repo: TestRepo]

      :ok = Polling.schedule({AlarmCounter, id}, :quick, 1, opts)

      {:ok, alarms} = Polling.list({AlarmCounter, id}, opts)
      assert length(alarms) == 1
    end

    test "cancelling during alarm fire doesn't break" do
      id = unique_id("edge")
      opts = [repo: TestRepo]

      {:ok, poller} = start_test_poller()
      {:ok, _pid} = DurableObject.ensure_started(AlarmCounter, id, opts)

      # Schedule and immediately try to cancel
      :ok = Polling.schedule({AlarmCounter, id}, :test_alarm, 0, opts)
      :ok = Polling.cancel({AlarmCounter, id}, :test_alarm, opts)

      # Trigger poller - alarm was cancelled, nothing should happen
      send(poller, :check_alarms)
      Process.sleep(100)

      {:ok, count} = AlarmCounter.get_alarm_count(id, opts)
      assert count == 0

      GenServer.stop(poller)
    end
  end

  # --- Claim-based Alarm Handling Tests ---

  describe "claim-based alarm handling" do
    test "atomic claim - two pollers race, only one wins" do
      id = unique_id("claim-race")
      opts = [repo: TestRepo]

      {:ok, poller1} = start_test_poller(claim_ttl: :timer.seconds(60))
      {:ok, poller2} = start_test_poller(claim_ttl: :timer.seconds(60))
      {:ok, _pid} = DurableObject.ensure_started(AlarmCounter, id, opts)

      # Schedule an alarm that's already overdue
      :ok = Polling.schedule({AlarmCounter, id}, :test_alarm, 0, opts)

      # Trigger both pollers simultaneously
      send(poller1, :check_alarms)
      send(poller2, :check_alarms)
      Process.sleep(200)

      # Handler should have been called exactly once (not twice)
      {:ok, count} = AlarmCounter.get_alarm_count(id, opts)
      assert count == 1

      # Alarm should be deleted
      {:ok, alarms} = Polling.list({AlarmCounter, id}, opts)
      assert alarms == []

      GenServer.stop(poller1)
      GenServer.stop(poller2)
    end

    test "reschedule preserves alarm - claimed_at cleared by upsert, delete is no-op" do
      id = unique_id("reschedule")
      opts = [repo: TestRepo]

      {:ok, poller} = start_test_poller(claim_ttl: :timer.seconds(60))
      {:ok, _pid} = DurableObject.ensure_started(AlarmCounter, id, opts)

      # Schedule the initial recurring alarm (which reschedules itself)
      :ok = Polling.schedule({AlarmCounter, id}, :recurring_alarm, 0, opts)

      # Fire it
      send(poller, :check_alarms)
      Process.sleep(100)

      # The handler should have scheduled a new alarm with claimed_at = nil
      {:ok, alarms} = Polling.list({AlarmCounter, id}, opts)
      assert length(alarms) == 1
      assert hd(alarms) |> elem(0) == :recurring_alarm

      # Verify the alarm record has claimed_at cleared
      [alarm_record] =
        TestRepo.all(from(a in Alarm, where: a.object_id == ^id))

      assert is_nil(alarm_record.claimed_at)

      GenServer.stop(poller)
    end

    test "stale claim retry - alarm becomes available after TTL" do
      id = unique_id("stale")
      opts = [repo: TestRepo]

      # Use a very short claim TTL for testing
      {:ok, poller} = start_test_poller(claim_ttl: 50)
      {:ok, _pid} = DurableObject.ensure_started(AlarmCounter, id, opts)

      # Schedule an overdue alarm
      :ok = Polling.schedule({AlarmCounter, id}, :test_alarm, 0, opts)

      # Manually claim the alarm to simulate a crash mid-execution
      [alarm_record] = TestRepo.all(from(a in Alarm, where: a.object_id == ^id))

      from(a in Alarm, where: a.id == ^alarm_record.id)
      |> TestRepo.update_all(set: [claimed_at: DateTime.utc_now()])

      # Verify it's claimed
      [claimed_record] = TestRepo.all(from(a in Alarm, where: a.object_id == ^id))
      assert not is_nil(claimed_record.claimed_at)

      # First poll - alarm is claimed, should be skipped
      send(poller, :check_alarms)
      Process.sleep(30)

      {:ok, count} = AlarmCounter.get_alarm_count(id, opts)
      assert count == 0

      # Wait for claim TTL to expire
      Process.sleep(60)

      # Second poll - claim is stale, alarm should fire
      send(poller, :check_alarms)
      Process.sleep(100)

      {:ok, count} = AlarmCounter.get_alarm_count(id, opts)
      assert count == 1

      # Alarm should be deleted
      {:ok, alarms} = Polling.list({AlarmCounter, id}, opts)
      assert alarms == []

      GenServer.stop(poller)
    end

    test "error leaves claim - handler fails, alarm stays for retry" do
      id = unique_id("error")
      opts = [repo: TestRepo]

      # Use a short claim TTL
      {:ok, poller} = start_test_poller(claim_ttl: 100)
      {:ok, _pid} = DurableObject.ensure_started(AlarmCounter, id, opts)

      # Schedule an alarm that will fail
      :ok = Polling.schedule({AlarmCounter, id}, :failing_alarm, 0, opts)

      # Fire it - handler will raise an error (capture logs to avoid noisy output)
      capture_log(fn ->
        send(poller, :check_alarms)
        Process.sleep(100)
      end)

      # Alarm should still exist with claimed_at set
      alarms = TestRepo.all(from(a in Alarm, where: a.object_id == ^id))
      assert length(alarms) == 1
      [alarm_record] = alarms
      assert not is_nil(alarm_record.claimed_at)

      GenServer.stop(poller)
    end

    test "successful fire deletes only if still claimed" do
      id = unique_id("delete-claimed")
      opts = [repo: TestRepo]

      {:ok, poller} = start_test_poller(claim_ttl: :timer.seconds(60))
      {:ok, _pid} = DurableObject.ensure_started(AlarmCounter, id, opts)

      # Schedule and fire a simple alarm
      :ok = Polling.schedule({AlarmCounter, id}, :test_alarm, 0, opts)

      send(poller, :check_alarms)
      Process.sleep(100)

      # Alarm should be fired and deleted
      {:ok, alarms} = Polling.list({AlarmCounter, id}, opts)
      assert alarms == []

      {:ok, count} = AlarmCounter.get_alarm_count(id, opts)
      assert count == 1

      GenServer.stop(poller)
    end

    test "slow poller does not delete alarm reclaimed by another poller" do
      id = unique_id("slow-poller")
      opts = [repo: TestRepo]

      {:ok, _pid} = DurableObject.ensure_started(AlarmCounter, id, opts)

      # Schedule an overdue alarm
      :ok = Polling.schedule({AlarmCounter, id}, :test_alarm, 0, opts)
      [alarm_record] = TestRepo.all(from(a in Alarm, where: a.object_id == ^id))

      # Simulate poller A claiming at time T1
      old_claim_time = DateTime.add(DateTime.utc_now(), -120, :second)

      from(a in Alarm, where: a.id == ^alarm_record.id)
      |> TestRepo.update_all(set: [claimed_at: old_claim_time])

      # Simulate poller B reclaiming after TTL expired (current time)
      new_claim_time = DateTime.utc_now()

      from(a in Alarm, where: a.id == ^alarm_record.id)
      |> TestRepo.update_all(set: [claimed_at: new_claim_time])

      # Poller A finishes late and tries to delete with old claim time
      # This simulates what delete_if_owned does - it should NOT delete
      # because claimed_at no longer matches
      {deleted_count, _} =
        from(a in Alarm,
          where: a.id == ^alarm_record.id,
          where: a.claimed_at == ^old_claim_time
        )
        |> TestRepo.delete_all()

      assert deleted_count == 0

      # Alarm should still exist with poller B's claim
      [remaining_alarm] = TestRepo.all(from(a in Alarm, where: a.object_id == ^id))
      assert DateTime.compare(remaining_alarm.claimed_at, new_claim_time) == :eq
    end
  end

  # --- Helpers ---

  defp start_test_poller(opts \\ []) do
    claim_ttl = Keyword.get(opts, :claim_ttl, :timer.seconds(60))

    DurableObject.Scheduler.Polling.Poller.start_link(
      repo: TestRepo,
      polling_interval: :timer.seconds(60),
      claim_ttl: claim_ttl,
      name: :"test_poller_#{System.unique_integer([:positive])}"
    )
  end
end
