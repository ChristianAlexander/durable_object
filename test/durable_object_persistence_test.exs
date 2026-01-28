defmodule DurableObjectPersistenceTest do
  use ExUnit.Case

  alias DurableObject.TestRepo

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
    Ecto.Adapters.SQL.Sandbox.mode(TestRepo, {:shared, self()})
    :ok
  end

  describe "call/5 with :repo option" do
    test "persists state across calls" do
      {:ok, 1} =
        DurableObject.call(PersistentCounter, "api-persist-1", :increment, [], repo: TestRepo)

      {:ok, 2} =
        DurableObject.call(PersistentCounter, "api-persist-1", :increment, [], repo: TestRepo)

      # Verify in database
      {:ok, object} =
        DurableObject.Storage.load(TestRepo, "#{PersistentCounter}", "api-persist-1")

      assert object.state == %{"count" => 2}
    end

    test "state survives stop and restart" do
      # Increment
      {:ok, 1} =
        DurableObject.call(PersistentCounter, "api-survive-1", :increment, [], repo: TestRepo)

      {:ok, 2} =
        DurableObject.call(PersistentCounter, "api-survive-1", :increment, [], repo: TestRepo)

      # Stop
      :ok = DurableObject.stop(PersistentCounter, "api-survive-1")
      assert DurableObject.whereis(PersistentCounter, "api-survive-1") == nil

      # Restart - state should be restored
      {:ok, 2} = DurableObject.call(PersistentCounter, "api-survive-1", :get, [], repo: TestRepo)

      {:ok, 3} =
        DurableObject.call(PersistentCounter, "api-survive-1", :increment, [], repo: TestRepo)
    end
  end

  describe "ensure_started/3 with :repo option" do
    test "loads state from database" do
      # Pre-populate
      {:ok, _} =
        DurableObject.Storage.save(TestRepo, "#{PersistentCounter}", "api-ensure-1", %{
          "count" => 100
        })

      # Start via ensure_started
      {:ok, _pid} =
        DurableObject.ensure_started(PersistentCounter, "api-ensure-1", repo: TestRepo)

      # Verify state loaded
      {:ok, 100} = DurableObject.call(PersistentCounter, "api-ensure-1", :get)
    end
  end
end
