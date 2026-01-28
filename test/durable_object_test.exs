defmodule DurableObjectTest do
  use ExUnit.Case, async: true
  import DurableObject.TestHelpers

  defmodule Counter do
    use DurableObject

    state do
      field(:count, :integer, default: 0)
    end

    handlers do
      handler(:increment)
      handler(:increment_by, args: [:n])
      handler(:get)
      handler(:reset)
    end

    def handle_increment(state) do
      new_count = state.count + 1
      {:reply, new_count, %{state | count: new_count}}
    end

    def handle_increment_by(n, state) do
      new_count = state.count + n
      {:reply, new_count, %{state | count: new_count}}
    end

    def handle_get(state) do
      {:reply, state.count, state}
    end

    def handle_reset(state) do
      {:noreply, %{state | count: 0}}
    end
  end

  describe "call/5" do
    test "starts object automatically on first call" do
      id = unique_id("auto")
      assert DurableObject.whereis(Counter, id) == nil
      assert {:ok, 1} = DurableObject.call(Counter, id, :increment)
      assert DurableObject.whereis(Counter, id) != nil
    end

    test "increments counter across calls" do
      id = unique_id("counter")
      {:ok, 1} = DurableObject.call(Counter, id, :increment)
      {:ok, 2} = DurableObject.call(Counter, id, :increment)
      {:ok, 3} = DurableObject.call(Counter, id, :increment)
      {:ok, 3} = DurableObject.call(Counter, id, :get)
    end

    test "passes arguments to handler" do
      id = unique_id("counter")
      {:ok, 5} = DurableObject.call(Counter, id, :increment_by, [5])
      {:ok, 15} = DurableObject.call(Counter, id, :increment_by, [10])
      {:ok, 15} = DurableObject.call(Counter, id, :get)
    end

    test "handles {:noreply, state}" do
      id = unique_id("counter")
      {:ok, 10} = DurableObject.call(Counter, id, :increment_by, [10])
      {:ok, :noreply} = DurableObject.call(Counter, id, :reset)
      {:ok, 0} = DurableObject.call(Counter, id, :get)
    end

    test "returns error for unknown handler" do
      assert {:error, {:unknown_handler, :nonexistent}} =
               DurableObject.call(Counter, unique_id("counter"), :nonexistent)
    end

    test "accepts timeout option" do
      {:ok, _} = DurableObject.call(Counter, unique_id("counter"), :increment, [], timeout: 1000)
    end

    test "accepts hibernate_after option" do
      {:ok, _} =
        DurableObject.call(Counter, unique_id("counter"), :increment, [], hibernate_after: 1000)
    end

    test "accepts shutdown_after option" do
      id = unique_id("counter")
      {:ok, _} = DurableObject.call(Counter, id, :increment, [], shutdown_after: 100)
      Process.sleep(150)
      assert DurableObject.whereis(Counter, id) == nil
    end
  end

  describe "ensure_started/3" do
    test "starts object if not running" do
      id = unique_id("ensure")
      assert DurableObject.whereis(Counter, id) == nil
      {:ok, pid} = DurableObject.ensure_started(Counter, id)
      assert DurableObject.whereis(Counter, id) == pid
    end

    test "returns existing pid if already running" do
      id = unique_id("ensure")
      {:ok, pid1} = DurableObject.ensure_started(Counter, id)
      {:ok, pid2} = DurableObject.ensure_started(Counter, id)
      assert pid1 == pid2
    end
  end

  describe "get_state/2" do
    test "returns state of running object" do
      id = unique_id("state")
      {:ok, _} = DurableObject.ensure_started(Counter, id)
      DurableObject.call(Counter, id, :increment_by, [42])
      assert DurableObject.get_state(Counter, id) == %{count: 42}
    end
  end

  describe "stop/3" do
    test "stops a running object" do
      id = unique_id("stop")
      {:ok, pid} = DurableObject.ensure_started(Counter, id)
      assert Process.alive?(pid)
      :ok = DurableObject.stop(Counter, id)
      refute Process.alive?(pid)
    end

    test "returns :ok for non-running object" do
      id = unique_id("stop")
      assert DurableObject.whereis(Counter, id) == nil
      assert :ok = DurableObject.stop(Counter, id)
    end
  end

  describe "whereis/2" do
    test "returns nil for non-running object" do
      assert DurableObject.whereis(Counter, unique_id("whereis")) == nil
    end

    test "returns pid for running object" do
      id = unique_id("whereis")
      {:ok, pid} = DurableObject.ensure_started(Counter, id)
      assert DurableObject.whereis(Counter, id) == pid
    end
  end

  describe "integration" do
    test "full lifecycle: start, use, stop, restart" do
      id = unique_id("lifecycle")

      # Start via call
      {:ok, 1} = DurableObject.call(Counter, id, :increment)
      {:ok, 2} = DurableObject.call(Counter, id, :increment)

      # Stop
      :ok = DurableObject.stop(Counter, id)
      assert DurableObject.whereis(Counter, id) == nil

      # Restart - state is reset (no persistence yet)
      {:ok, 1} = DurableObject.call(Counter, id, :increment)
    end
  end

  describe "default_repo/0" do
    test "returns nil when not configured" do
      # Test config has no default repo set
      assert DurableObject.default_repo() == nil
    end
  end
end
