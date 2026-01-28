defmodule DurableObject.ServerTest do
  use ExUnit.Case, async: true

  alias DurableObject.Server
  import DurableObject.TestHelpers

  defmodule TestHandler do
  end

  defmodule CounterHandler do
    def handle_increment(state) do
      new_count = Map.get(state, :count, 0) + 1
      {:reply, new_count, Map.put(state, :count, new_count)}
    end

    def handle_increment_by(amount, state) do
      new_count = Map.get(state, :count, 0) + amount
      {:reply, new_count, Map.put(state, :count, new_count)}
    end

    def handle_get(state) do
      {:reply, Map.get(state, :count, 0), state}
    end

    def handle_get_readonly(state) do
      {:reply, Map.get(state, :count, 0)}
    end

    def handle_reset(state) do
      {:noreply, Map.put(state, :count, 0)}
    end

    def handle_fail(_state) do
      {:error, :something_went_wrong}
    end
  end

  describe "start_link/1" do
    test "registers process with via_tuple" do
      id = unique_id("start")
      {:ok, pid} = Server.start_link(module: TestHandler, object_id: id)

      assert pid == GenServer.whereis(Server.via_tuple(TestHandler, id))
    end

    test "requires module option" do
      assert_raise KeyError, fn ->
        Server.start_link(object_id: unique_id("no-mod"))
      end
    end

    test "requires object_id option" do
      assert_raise KeyError, fn ->
        Server.start_link(module: TestHandler)
      end
    end

    test "returns error for duplicate registration" do
      id = unique_id("dup")
      {:ok, _pid} = Server.start_link(module: TestHandler, object_id: id)

      assert {:error, {:already_started, _}} =
               Server.start_link(module: TestHandler, object_id: id)
    end

    test "accepts hibernate_after option" do
      {:ok, pid} =
        Server.start_link(module: TestHandler, object_id: unique_id("hib"), hibernate_after: 1000)

      assert Process.alive?(pid)
    end

    test "uses default hibernate_after of 5 minutes" do
      assert Server.default_hibernate_after() == :timer.minutes(5)
    end
  end

  describe "get_state/2 and put_state/3" do
    test "initial state is empty map" do
      id = unique_id("state")
      {:ok, _pid} = Server.start_link(module: TestHandler, object_id: id)

      assert Server.get_state(TestHandler, id) == %{}
    end

    test "put_state updates state" do
      id = unique_id("state")
      {:ok, _pid} = Server.start_link(module: TestHandler, object_id: id)

      assert :ok = Server.put_state(TestHandler, id, %{count: 5})
      assert Server.get_state(TestHandler, id) == %{count: 5}
    end

    test "put_state replaces entire state" do
      id = unique_id("state")
      {:ok, _pid} = Server.start_link(module: TestHandler, object_id: id)

      Server.put_state(TestHandler, id, %{a: 1, b: 2})
      Server.put_state(TestHandler, id, %{c: 3})

      assert Server.get_state(TestHandler, id) == %{c: 3}
    end
  end

  describe "call/4" do
    test "dispatches to handle_<name> function" do
      id = unique_id("call")
      {:ok, _pid} = Server.start_link(module: CounterHandler, object_id: id)

      assert {:ok, 1} = Server.call(CounterHandler, id, :increment)
      assert {:ok, 2} = Server.call(CounterHandler, id, :increment)
    end

    test "passes args to handler" do
      id = unique_id("call")
      {:ok, _pid} = Server.start_link(module: CounterHandler, object_id: id)

      assert {:ok, 5} = Server.call(CounterHandler, id, :increment_by, [5])
      assert {:ok, 15} = Server.call(CounterHandler, id, :increment_by, [10])
    end

    test "handles {:reply, result, new_state}" do
      id = unique_id("call")
      {:ok, _pid} = Server.start_link(module: CounterHandler, object_id: id)

      assert {:ok, 1} = Server.call(CounterHandler, id, :increment)
      assert {:ok, 1} = Server.call(CounterHandler, id, :get)
    end

    test "handles {:reply, result} for read-only operations" do
      id = unique_id("call")
      {:ok, _pid} = Server.start_link(module: CounterHandler, object_id: id)

      Server.call(CounterHandler, id, :increment_by, [5])
      assert {:ok, 5} = Server.call(CounterHandler, id, :get_readonly)
    end

    test "handles {:noreply, new_state}" do
      id = unique_id("call")
      {:ok, _pid} = Server.start_link(module: CounterHandler, object_id: id)

      Server.call(CounterHandler, id, :increment_by, [10])
      assert {:ok, :noreply} = Server.call(CounterHandler, id, :reset)
      assert {:ok, 0} = Server.call(CounterHandler, id, :get)
    end

    test "handles {:error, reason}" do
      id = unique_id("call")
      {:ok, _pid} = Server.start_link(module: CounterHandler, object_id: id)

      assert {:error, :something_went_wrong} = Server.call(CounterHandler, id, :fail)
    end

    test "returns error for unknown handler" do
      id = unique_id("call")
      {:ok, _pid} = Server.start_link(module: CounterHandler, object_id: id)

      assert {:error, {:unknown_handler, :nonexistent}} =
               Server.call(CounterHandler, id, :nonexistent)
    end
  end

  describe "ensure_started/3" do
    test "starts object if not running" do
      id = unique_id("ensure")
      assert Server.whereis(CounterHandler, id) == nil

      {:ok, pid} = Server.ensure_started(CounterHandler, id)

      assert Process.alive?(pid)
      assert Server.whereis(CounterHandler, id) == pid
    end

    test "returns existing pid if already running" do
      id = unique_id("ensure")
      {:ok, pid1} = Server.ensure_started(CounterHandler, id)
      {:ok, pid2} = Server.ensure_started(CounterHandler, id)

      assert pid1 == pid2
    end

    test "passes opts to start_link" do
      id = unique_id("ensure")
      {:ok, pid} = Server.ensure_started(CounterHandler, id, hibernate_after: 1000)

      assert Process.alive?(pid)
    end

    test "object is usable after ensure_started" do
      id = unique_id("ensure")
      {:ok, _pid} = Server.ensure_started(CounterHandler, id)

      assert {:ok, 1} = Server.call(CounterHandler, id, :increment)
      assert {:ok, 1} = Server.call(CounterHandler, id, :get)
    end
  end

  describe "whereis/2" do
    test "returns nil for non-running object" do
      assert Server.whereis(TestHandler, unique_id("whereis")) == nil
    end

    test "returns pid for running object" do
      id = unique_id("whereis")
      {:ok, pid} = Server.start_link(module: TestHandler, object_id: id)

      assert Server.whereis(TestHandler, id) == pid
    end
  end

  describe "shutdown_after" do
    test "process shuts down after timeout" do
      {:ok, pid} =
        Server.start_link(module: TestHandler, object_id: unique_id("shutdown"), shutdown_after: 50)

      assert Process.alive?(pid)
      Process.sleep(100)
      refute Process.alive?(pid)
    end

    test "activity resets shutdown timer" do
      id = unique_id("shutdown")
      {:ok, pid} =
        Server.start_link(module: CounterHandler, object_id: id, shutdown_after: 100)

      # Activity at 30ms
      Process.sleep(30)
      Server.call(CounterHandler, id, :increment)

      # At 80ms total (50ms since activity), should still be alive
      Process.sleep(50)
      assert Process.alive?(pid)

      # At 180ms total (100ms since last activity), should be dead
      Process.sleep(100)
      refute Process.alive?(pid)
    end

    test "nil shutdown_after means no auto-shutdown" do
      {:ok, pid} =
        Server.start_link(module: TestHandler, object_id: unique_id("shutdown"), shutdown_after: nil)

      Process.sleep(50)
      assert Process.alive?(pid)
    end

    test "no shutdown_after option means no auto-shutdown" do
      {:ok, pid} = Server.start_link(module: TestHandler, object_id: unique_id("shutdown"))

      Process.sleep(50)
      assert Process.alive?(pid)
    end
  end
end
