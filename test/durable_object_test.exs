defmodule DurableObjectTest do
  use ExUnit.Case, async: true

  defmodule Counter do
    def handle_increment(state) do
      new_count = Map.get(state, :count, 0) + 1
      {:reply, new_count, Map.put(state, :count, new_count)}
    end

    def handle_increment_by(n, state) do
      new_count = Map.get(state, :count, 0) + n
      {:reply, new_count, Map.put(state, :count, new_count)}
    end

    def handle_get(state) do
      {:reply, Map.get(state, :count, 0), state}
    end

    def handle_reset(state) do
      {:noreply, Map.put(state, :count, 0)}
    end
  end

  describe "call/5" do
    test "starts object automatically on first call" do
      assert DurableObject.whereis(Counter, "auto-start-1") == nil
      assert {:ok, 1} = DurableObject.call(Counter, "auto-start-1", :increment)
      assert DurableObject.whereis(Counter, "auto-start-1") != nil
    end

    test "increments counter across calls" do
      {:ok, 1} = DurableObject.call(Counter, "counter-1", :increment)
      {:ok, 2} = DurableObject.call(Counter, "counter-1", :increment)
      {:ok, 3} = DurableObject.call(Counter, "counter-1", :increment)
      {:ok, 3} = DurableObject.call(Counter, "counter-1", :get)
    end

    test "passes arguments to handler" do
      {:ok, 5} = DurableObject.call(Counter, "counter-2", :increment_by, [5])
      {:ok, 15} = DurableObject.call(Counter, "counter-2", :increment_by, [10])
      {:ok, 15} = DurableObject.call(Counter, "counter-2", :get)
    end

    test "handles {:noreply, state}" do
      {:ok, 10} = DurableObject.call(Counter, "counter-3", :increment_by, [10])
      {:ok, :noreply} = DurableObject.call(Counter, "counter-3", :reset)
      {:ok, 0} = DurableObject.call(Counter, "counter-3", :get)
    end

    test "returns error for unknown handler" do
      assert {:error, {:unknown_handler, :nonexistent}} =
               DurableObject.call(Counter, "counter-4", :nonexistent)
    end

    test "accepts timeout option" do
      {:ok, _} = DurableObject.call(Counter, "counter-5", :increment, [], timeout: 1000)
    end

    test "accepts hibernate_after option" do
      {:ok, _} = DurableObject.call(Counter, "counter-6", :increment, [], hibernate_after: 1000)
    end

    test "accepts shutdown_after option" do
      {:ok, _} = DurableObject.call(Counter, "counter-7", :increment, [], shutdown_after: 100)
      Process.sleep(150)
      assert DurableObject.whereis(Counter, "counter-7") == nil
    end
  end

  describe "ensure_started/3" do
    test "starts object if not running" do
      assert DurableObject.whereis(Counter, "ensure-1") == nil
      {:ok, pid} = DurableObject.ensure_started(Counter, "ensure-1")
      assert DurableObject.whereis(Counter, "ensure-1") == pid
    end

    test "returns existing pid if already running" do
      {:ok, pid1} = DurableObject.ensure_started(Counter, "ensure-2")
      {:ok, pid2} = DurableObject.ensure_started(Counter, "ensure-2")
      assert pid1 == pid2
    end
  end

  describe "get_state/2" do
    test "returns state of running object" do
      {:ok, _} = DurableObject.ensure_started(Counter, "state-1")
      DurableObject.call(Counter, "state-1", :increment_by, [42])
      assert DurableObject.get_state(Counter, "state-1") == %{count: 42}
    end
  end

  describe "stop/3" do
    test "stops a running object" do
      {:ok, pid} = DurableObject.ensure_started(Counter, "stop-1")
      assert Process.alive?(pid)
      :ok = DurableObject.stop(Counter, "stop-1")
      refute Process.alive?(pid)
    end

    test "returns :ok for non-running object" do
      assert DurableObject.whereis(Counter, "stop-not-running") == nil
      assert :ok = DurableObject.stop(Counter, "stop-not-running")
    end
  end

  describe "whereis/2" do
    test "returns nil for non-running object" do
      assert DurableObject.whereis(Counter, "whereis-not-running") == nil
    end

    test "returns pid for running object" do
      {:ok, pid} = DurableObject.ensure_started(Counter, "whereis-1")
      assert DurableObject.whereis(Counter, "whereis-1") == pid
    end
  end

  describe "integration" do
    test "full lifecycle: start, use, stop, restart" do
      # Start via call
      {:ok, 1} = DurableObject.call(Counter, "lifecycle-1", :increment)
      {:ok, 2} = DurableObject.call(Counter, "lifecycle-1", :increment)

      # Stop
      :ok = DurableObject.stop(Counter, "lifecycle-1")
      assert DurableObject.whereis(Counter, "lifecycle-1") == nil

      # Restart - state is reset (no persistence yet)
      {:ok, 1} = DurableObject.call(Counter, "lifecycle-1", :increment)
    end
  end
end
