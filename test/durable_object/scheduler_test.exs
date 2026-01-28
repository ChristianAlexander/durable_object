defmodule DurableObject.SchedulerTest do
  use ExUnit.Case, async: false

  alias DurableObject.Scheduler.Polling
  alias DurableObject.Storage.Schemas.Alarm
  alias DurableObject.TestRepo

  import Ecto.Query

  @moduletag :scheduler

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)
    # Allow the Poller process to use our connection
    Ecto.Adapters.SQL.Sandbox.mode(TestRepo, {:shared, self()})
    :ok
  end

  defmodule TestCounter do
    def handle_increment(state) do
      count = Map.get(state, :count, 0) + 1
      {:reply, count, Map.put(state, :count, count)}
    end

    def handle_get(state) do
      {:reply, Map.get(state, :count, 0), state}
    end

    def handle_alarm(:test_alarm, state) do
      count = Map.get(state, :alarm_count, 0) + 1
      {:noreply, Map.put(state, :alarm_count, count)}
    end

    def handle_alarm(:recurring_alarm, state) do
      count = Map.get(state, :recurring_count, 0) + 1
      new_state = Map.put(state, :recurring_count, count)
      # Schedule another alarm in 100ms
      {:noreply, new_state, {:schedule_alarm, :recurring_alarm, 100}}
    end
  end

  describe "Polling.schedule/4" do
    test "schedules an alarm in the database" do
      opts = [repo: DurableObject.TestRepo]

      :ok = Polling.schedule({TestCounter, "test-1"}, :my_alarm, 1000, opts)

      alarms =
        from(a in Alarm, where: a.object_id == "test-1")
        |> DurableObject.TestRepo.all()

      assert length(alarms) == 1
      [alarm] = alarms
      assert alarm.object_type == "Elixir.DurableObject.SchedulerTest.TestCounter"
      assert alarm.alarm_name == "my_alarm"
      # Should be scheduled ~1 second from now
      assert DateTime.diff(alarm.scheduled_at, DateTime.utc_now(), :millisecond) >= 900
    end

    test "replaces existing alarm with same name" do
      opts = [repo: DurableObject.TestRepo]

      :ok = Polling.schedule({TestCounter, "test-2"}, :my_alarm, 5000, opts)
      :ok = Polling.schedule({TestCounter, "test-2"}, :my_alarm, 1000, opts)

      alarms =
        from(a in Alarm, where: a.object_id == "test-2")
        |> DurableObject.TestRepo.all()

      assert length(alarms) == 1
      [alarm] = alarms
      # Should have the newer (shorter) delay
      assert DateTime.diff(alarm.scheduled_at, DateTime.utc_now(), :millisecond) < 2000
    end

    test "allows multiple different alarms for same object" do
      opts = [repo: DurableObject.TestRepo]

      :ok = Polling.schedule({TestCounter, "test-3"}, :alarm_a, 1000, opts)
      :ok = Polling.schedule({TestCounter, "test-3"}, :alarm_b, 2000, opts)

      alarms =
        from(a in Alarm, where: a.object_id == "test-3", order_by: a.alarm_name)
        |> DurableObject.TestRepo.all()

      assert length(alarms) == 2
      assert Enum.map(alarms, & &1.alarm_name) == ["alarm_a", "alarm_b"]
    end
  end

  describe "Polling.cancel/4" do
    test "cancels a scheduled alarm" do
      opts = [repo: DurableObject.TestRepo]

      :ok = Polling.schedule({TestCounter, "test-4"}, :my_alarm, 1000, opts)
      :ok = Polling.cancel({TestCounter, "test-4"}, :my_alarm, opts)

      alarms =
        from(a in Alarm, where: a.object_id == "test-4")
        |> DurableObject.TestRepo.all()

      assert alarms == []
    end

    test "returns :ok even if alarm doesn't exist" do
      opts = [repo: DurableObject.TestRepo]
      assert :ok = Polling.cancel({TestCounter, "nonexistent"}, :no_alarm, opts)
    end
  end

  describe "Polling.cancel_all/3" do
    test "cancels all alarms for an object" do
      opts = [repo: DurableObject.TestRepo]

      :ok = Polling.schedule({TestCounter, "test-5"}, :alarm_a, 1000, opts)
      :ok = Polling.schedule({TestCounter, "test-5"}, :alarm_b, 2000, opts)
      :ok = Polling.cancel_all({TestCounter, "test-5"}, opts)

      alarms =
        from(a in Alarm, where: a.object_id == "test-5")
        |> DurableObject.TestRepo.all()

      assert alarms == []
    end
  end

  describe "Polling.list/3" do
    test "lists all alarms for an object" do
      opts = [repo: DurableObject.TestRepo]

      :ok = Polling.schedule({TestCounter, "test-6"}, :alarm_a, 1000, opts)
      :ok = Polling.schedule({TestCounter, "test-6"}, :alarm_b, 2000, opts)

      {:ok, alarms} = Polling.list({TestCounter, "test-6"}, opts)

      assert length(alarms) == 2
      assert Enum.map(alarms, &elem(&1, 0)) == [:alarm_a, :alarm_b]
    end

    test "returns empty list when no alarms exist" do
      opts = [repo: DurableObject.TestRepo]
      {:ok, alarms} = Polling.list({TestCounter, "nonexistent"}, opts)
      assert alarms == []
    end
  end

  describe "Poller" do
    test "fires overdue alarms" do
      opts = [repo: TestRepo]

      # Start our own test poller with the test repo
      {:ok, poller} =
        DurableObject.Scheduler.Polling.Poller.start_link(
          repo: TestRepo,
          polling_interval: :timer.seconds(60),
          name: :test_poller
        )

      # Start the object first
      {:ok, _pid} = DurableObject.ensure_started(TestCounter, "poll-test", opts)

      # Schedule an alarm that's already overdue
      :ok = Polling.schedule({TestCounter, "poll-test"}, :test_alarm, 0, opts)

      # Manually trigger the poller
      send(poller, :check_alarms)

      # Give it time to process
      Process.sleep(100)

      # The alarm should have fired and been deleted
      {:ok, alarms} = Polling.list({TestCounter, "poll-test"}, opts)
      assert alarms == []

      # And the alarm handler should have updated state
      state = DurableObject.get_state(TestCounter, "poll-test")
      assert Map.get(state, :alarm_count, 0) == 1

      # Clean up
      GenServer.stop(poller)
    end
  end
end
