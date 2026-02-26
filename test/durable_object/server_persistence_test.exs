defmodule DurableObject.ServerPersistenceTest do
  use ExUnit.Case

  alias DurableObject.{Server, Storage, TestRepo}
  import DurableObject.TestHelpers

  defmodule PersistentCounter do
    use DurableObject

    state do
      field(:count, :integer, default: 0)
    end

    handlers do
      handler(:increment)
      handler(:get)
    end

    def handle_increment(state) do
      new_count = state.count + 1
      {:reply, new_count, %{state | count: new_count}}
    end

    def handle_get(state) do
      {:reply, state.count, state}
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
      id = unique_id("load")

      # Pre-populate the database with string keys (as stored in JSON)
      {:ok, _} =
        Storage.save(TestRepo, "#{PersistentCounter}", id, %{"count" => 42})

      # Start the server - it should load the state
      {:ok, _pid} =
        Server.start_link(
          module: PersistentCounter,
          object_id: id,
          repo: TestRepo
        )

      # Verify state was loaded
      assert {:ok, 42} = Server.call(PersistentCounter, id, :get)
    end

    test "persists state after handler calls" do
      id = unique_id("persist")

      {:ok, _pid} =
        Server.start_link(
          module: PersistentCounter,
          object_id: id,
          repo: TestRepo
        )

      # Make some calls
      {:ok, 1} = Server.call(PersistentCounter, id, :increment)
      {:ok, 2} = Server.call(PersistentCounter, id, :increment)

      # Verify persisted in database
      {:ok, object} = Storage.load(TestRepo, "#{PersistentCounter}", id)
      assert object.state == %{"count" => 2}
    end

    test "state survives restart" do
      id = unique_id("survive")

      # Start, increment, stop
      {:ok, pid} =
        Server.start_link(
          module: PersistentCounter,
          object_id: id,
          repo: TestRepo
        )

      {:ok, 1} = Server.call(PersistentCounter, id, :increment)
      {:ok, 2} = Server.call(PersistentCounter, id, :increment)
      GenServer.stop(pid)

      # Restart - state should be restored
      {:ok, _pid} =
        Server.start_link(
          module: PersistentCounter,
          object_id: id,
          repo: TestRepo
        )

      assert {:ok, 2} = Server.call(PersistentCounter, id, :get)
      assert {:ok, 3} = Server.call(PersistentCounter, id, :increment)
    end
  end

  defmodule SerdeCounter do
    use DurableObject

    state do
      field(:count, :integer, default: 0)
    end

    handlers do
      handler(:increment)
      handler(:get_state)
    end

    def handle_increment(state) do
      {:reply, :ok, %{state | count: state.count + 1}}
    end

    def handle_get_state(state) do
      {:reply, state, state}
    end
  end

  describe "state serde through sqlite" do
    test "state persists and rehydrates correctly" do
      id = unique_id("serde")

      {:ok, :ok} = SerdeCounter.increment(id, repo: TestRepo)
      {:ok, :ok} = SerdeCounter.increment(id, repo: TestRepo)
      {:ok, :ok} = SerdeCounter.increment(id, repo: TestRepo)
      DurableObject.stop(SerdeCounter, id)

      {:ok, state} = SerdeCounter.get_state(id, repo: TestRepo)
      assert state.id == id
      assert state.count == 3
    end
  end

  describe "without :repo option" do
    test "works without persistence" do
      id = unique_id("no-repo")

      {:ok, _pid} =
        Server.start_link(
          module: PersistentCounter,
          object_id: id
        )

      {:ok, 1} = Server.call(PersistentCounter, id, :increment)
      {:ok, 2} = Server.call(PersistentCounter, id, :increment)
      {:ok, 2} = Server.call(PersistentCounter, id, :get)
    end
  end
end
