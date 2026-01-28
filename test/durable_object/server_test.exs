defmodule DurableObject.ServerTest do
  use ExUnit.Case, async: true

  alias DurableObject.Server

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

    def handle_reset(state) do
      {:noreply, Map.put(state, :count, 0)}
    end

    def handle_fail(_state) do
      {:error, :something_went_wrong}
    end
  end

  describe "start_link/1" do
    test "registers process with via_tuple" do
      {:ok, pid} = Server.start_link(module: TestHandler, object_id: "test-1")

      assert pid == GenServer.whereis(Server.via_tuple(TestHandler, "test-1"))
    end

    test "requires module option" do
      assert_raise KeyError, fn ->
        Server.start_link(object_id: "test-1")
      end
    end

    test "requires object_id option" do
      assert_raise KeyError, fn ->
        Server.start_link(module: TestHandler)
      end
    end

    test "returns error for duplicate registration" do
      {:ok, _pid} = Server.start_link(module: TestHandler, object_id: "dup-test")

      assert {:error, {:already_started, _}} =
               Server.start_link(module: TestHandler, object_id: "dup-test")
    end

    test "accepts hibernate_after option" do
      {:ok, pid} =
        Server.start_link(module: TestHandler, object_id: "hib-1", hibernate_after: 1000)

      assert Process.alive?(pid)
    end

    test "uses default hibernate_after of 5 minutes" do
      assert Server.default_hibernate_after() == :timer.minutes(5)
    end
  end

  describe "get_state/2 and put_state/3" do
    test "initial state is empty map" do
      {:ok, _pid} = Server.start_link(module: TestHandler, object_id: "state-1")

      assert Server.get_state(TestHandler, "state-1") == %{}
    end

    test "put_state updates state" do
      {:ok, _pid} = Server.start_link(module: TestHandler, object_id: "state-2")

      assert :ok = Server.put_state(TestHandler, "state-2", %{count: 5})
      assert Server.get_state(TestHandler, "state-2") == %{count: 5}
    end

    test "put_state replaces entire state" do
      {:ok, _pid} = Server.start_link(module: TestHandler, object_id: "state-3")

      Server.put_state(TestHandler, "state-3", %{a: 1, b: 2})
      Server.put_state(TestHandler, "state-3", %{c: 3})

      assert Server.get_state(TestHandler, "state-3") == %{c: 3}
    end
  end

  describe "call/4" do
    test "dispatches to handle_<name> function" do
      {:ok, _pid} = Server.start_link(module: CounterHandler, object_id: "call-1")

      assert {:ok, 1} = Server.call(CounterHandler, "call-1", :increment)
      assert {:ok, 2} = Server.call(CounterHandler, "call-1", :increment)
    end

    test "passes args to handler" do
      {:ok, _pid} = Server.start_link(module: CounterHandler, object_id: "call-2")

      assert {:ok, 5} = Server.call(CounterHandler, "call-2", :increment_by, [5])
      assert {:ok, 15} = Server.call(CounterHandler, "call-2", :increment_by, [10])
    end

    test "handles {:reply, result, new_state}" do
      {:ok, _pid} = Server.start_link(module: CounterHandler, object_id: "call-3")

      assert {:ok, 1} = Server.call(CounterHandler, "call-3", :increment)
      assert {:ok, 1} = Server.call(CounterHandler, "call-3", :get)
    end

    test "handles {:noreply, new_state}" do
      {:ok, _pid} = Server.start_link(module: CounterHandler, object_id: "call-4")

      Server.call(CounterHandler, "call-4", :increment_by, [10])
      assert {:ok, :noreply} = Server.call(CounterHandler, "call-4", :reset)
      assert {:ok, 0} = Server.call(CounterHandler, "call-4", :get)
    end

    test "handles {:error, reason}" do
      {:ok, _pid} = Server.start_link(module: CounterHandler, object_id: "call-5")

      assert {:error, :something_went_wrong} = Server.call(CounterHandler, "call-5", :fail)
    end

    test "returns error for unknown handler" do
      {:ok, _pid} = Server.start_link(module: CounterHandler, object_id: "call-6")

      assert {:error, {:unknown_handler, :nonexistent}} =
               Server.call(CounterHandler, "call-6", :nonexistent)
    end
  end

  describe "ensure_started/3" do
    test "starts object if not running" do
      assert Server.whereis(CounterHandler, "ensure-1") == nil

      {:ok, pid} = Server.ensure_started(CounterHandler, "ensure-1")

      assert Process.alive?(pid)
      assert Server.whereis(CounterHandler, "ensure-1") == pid
    end

    test "returns existing pid if already running" do
      {:ok, pid1} = Server.ensure_started(CounterHandler, "ensure-2")
      {:ok, pid2} = Server.ensure_started(CounterHandler, "ensure-2")

      assert pid1 == pid2
    end

    test "passes opts to start_link" do
      {:ok, pid} = Server.ensure_started(CounterHandler, "ensure-3", hibernate_after: 1000)

      assert Process.alive?(pid)
    end

    test "object is usable after ensure_started" do
      {:ok, _pid} = Server.ensure_started(CounterHandler, "ensure-4")

      assert {:ok, 1} = Server.call(CounterHandler, "ensure-4", :increment)
      assert {:ok, 1} = Server.call(CounterHandler, "ensure-4", :get)
    end
  end

  describe "whereis/2" do
    test "returns nil for non-running object" do
      assert Server.whereis(TestHandler, "whereis-not-running") == nil
    end

    test "returns pid for running object" do
      {:ok, pid} = Server.start_link(module: TestHandler, object_id: "whereis-1")

      assert Server.whereis(TestHandler, "whereis-1") == pid
    end
  end
end
