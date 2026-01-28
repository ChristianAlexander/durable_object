defmodule DurableObject.ServerPersistenceTest do
  use ExUnit.Case

  alias DurableObject.{Server, Storage, TestRepo}

  defmodule PersistentCounter do
    def handle_increment(state) do
      new_count = Map.get(state, "count", 0) + 1
      {:reply, new_count, Map.put(state, "count", new_count)}
    end

    def handle_get(state) do
      {:reply, Map.get(state, "count", 0), state}
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)
    # Allow all spawned processes to use this connection
    Ecto.Adapters.SQL.Sandbox.mode(TestRepo, {:shared, self()})
    :ok
  end

  describe "persistence with :repo option" do
    test "loads state from database on startup" do
      # Pre-populate the database
      {:ok, _} =
        Storage.save(TestRepo, "#{PersistentCounter}", "load-1", %{"count" => 42})

      # Start the server - it should load the state
      {:ok, _pid} =
        Server.start_link(
          module: PersistentCounter,
          object_id: "load-1",
          repo: TestRepo
        )

      # Verify state was loaded
      assert {:ok, 42} = Server.call(PersistentCounter, "load-1", :get)
    end

    test "persists state after handler calls" do
      {:ok, _pid} =
        Server.start_link(
          module: PersistentCounter,
          object_id: "persist-1",
          repo: TestRepo
        )

      # Make some calls
      {:ok, 1} = Server.call(PersistentCounter, "persist-1", :increment)
      {:ok, 2} = Server.call(PersistentCounter, "persist-1", :increment)

      # Verify persisted in database
      {:ok, object} = Storage.load(TestRepo, "#{PersistentCounter}", "persist-1")
      assert object.state == %{"count" => 2}
    end

    test "releases lock on terminate" do
      {:ok, pid} =
        Server.start_link(
          module: PersistentCounter,
          object_id: "lock-1",
          repo: TestRepo
        )

      # Make a call to ensure it's persisted
      {:ok, 1} = Server.call(PersistentCounter, "lock-1", :increment)

      # Verify locked
      {:ok, object} = Storage.load(TestRepo, "#{PersistentCounter}", "lock-1")
      assert object.locked_by != nil

      # Stop the server
      GenServer.stop(pid)

      # Verify lock released
      {:ok, object} = Storage.load(TestRepo, "#{PersistentCounter}", "lock-1")
      assert object.locked_by == nil
    end

    test "state survives restart" do
      # Start, increment, stop
      {:ok, pid} =
        Server.start_link(
          module: PersistentCounter,
          object_id: "survive-1",
          repo: TestRepo
        )

      {:ok, 1} = Server.call(PersistentCounter, "survive-1", :increment)
      {:ok, 2} = Server.call(PersistentCounter, "survive-1", :increment)
      GenServer.stop(pid)

      # Restart - state should be restored
      {:ok, _pid} =
        Server.start_link(
          module: PersistentCounter,
          object_id: "survive-1",
          repo: TestRepo
        )

      assert {:ok, 2} = Server.call(PersistentCounter, "survive-1", :get)
      assert {:ok, 3} = Server.call(PersistentCounter, "survive-1", :increment)
    end
  end

  describe "without :repo option" do
    test "works without persistence" do
      {:ok, _pid} =
        Server.start_link(
          module: PersistentCounter,
          object_id: "no-repo-1"
        )

      {:ok, 1} = Server.call(PersistentCounter, "no-repo-1", :increment)
      {:ok, 2} = Server.call(PersistentCounter, "no-repo-1", :increment)
      {:ok, 2} = Server.call(PersistentCounter, "no-repo-1", :get)
    end
  end
end
