defmodule DurableObjectPersistenceTest do
  use ExUnit.Case

  alias DurableObject.TestRepo
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
    Ecto.Adapters.SQL.Sandbox.mode(TestRepo, {:shared, self()})
    :ok
  end

  describe "call/5 with :repo option" do
    test "persists state across calls" do
      id = unique_id("api-persist")

      {:ok, 1} =
        DurableObject.call(PersistentCounter, id, :increment, [], repo: TestRepo)

      {:ok, 2} =
        DurableObject.call(PersistentCounter, id, :increment, [], repo: TestRepo)

      # Verify in database
      {:ok, object} =
        DurableObject.Storage.load(TestRepo, "#{PersistentCounter}", id)

      assert object.state == %{"count" => 2}
    end

    test "state survives stop and restart" do
      id = unique_id("api-survive")

      # Increment
      {:ok, 1} =
        DurableObject.call(PersistentCounter, id, :increment, [], repo: TestRepo)

      {:ok, 2} =
        DurableObject.call(PersistentCounter, id, :increment, [], repo: TestRepo)

      # Stop
      :ok = DurableObject.stop(PersistentCounter, id)
      assert DurableObject.whereis(PersistentCounter, id) == nil

      # Restart - state should be restored
      {:ok, 2} = DurableObject.call(PersistentCounter, id, :get, [], repo: TestRepo)

      {:ok, 3} =
        DurableObject.call(PersistentCounter, id, :increment, [], repo: TestRepo)
    end
  end

  describe "ensure_started/3 with :repo option" do
    test "loads state from database" do
      id = unique_id("api-ensure")

      # Pre-populate with string keys (as they'd be stored in JSON)
      {:ok, _} =
        DurableObject.Storage.save(TestRepo, "#{PersistentCounter}", id, %{
          "count" => 100
        })

      # Start via ensure_started
      {:ok, _pid} =
        DurableObject.ensure_started(PersistentCounter, id, repo: TestRepo)

      # Verify state loaded
      {:ok, 100} = DurableObject.call(PersistentCounter, id, :get)
    end
  end
end
