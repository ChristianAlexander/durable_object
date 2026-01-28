defmodule DurableObject.IntegrationTest do
  use ExUnit.Case, async: true

  # Define a complete Durable Object using the DSL
  defmodule TestCounter do
    use DurableObject

    state do
      field(:count, :integer, default: 0)
      field(:name, :string, default: "unnamed")
    end

    handlers do
      handler(:increment, args: [:amount])
      handler(:decrement, args: [:amount])
      handler(:set_name, args: [:name])
      handler(:get)
      handler(:reset)
    end

    options do
      hibernate_after(300_000)
    end

    def handle_increment(amount, state) do
      new_count = Map.get(state, :count, 0) + amount
      {:reply, new_count, Map.put(state, :count, new_count)}
    end

    def handle_decrement(amount, state) do
      new_count = max(0, Map.get(state, :count, 0) - amount)
      {:reply, new_count, Map.put(state, :count, new_count)}
    end

    def handle_set_name(name, state) do
      {:reply, :ok, Map.put(state, :name, name)}
    end

    def handle_get(state) do
      {:reply, state, state}
    end

    def handle_reset(state) do
      {:noreply, Map.put(state, :count, 0)}
    end
  end

  describe "DSL integration" do
    setup do
      Code.ensure_loaded!(TestCounter)
      :ok
    end

    test "module defines __durable_object__/1 introspection" do
      assert TestCounter.__durable_object__(:hibernate_after) == 300_000
      assert TestCounter.__durable_object__(:shutdown_after) == nil
      assert TestCounter.__durable_object__(:default_state) == %{count: 0, name: "unnamed"}

      fields = TestCounter.__durable_object__(:fields)
      assert length(fields) == 2
      assert Enum.any?(fields, &(&1.name == :count))
      assert Enum.any?(fields, &(&1.name == :name))

      handlers = TestCounter.__durable_object__(:handlers)
      assert length(handlers) == 5
    end

    test "module generates client API functions" do
      assert function_exported?(TestCounter, :increment, 2)
      assert function_exported?(TestCounter, :increment, 3)
      assert function_exported?(TestCounter, :decrement, 2)
      assert function_exported?(TestCounter, :decrement, 3)
      assert function_exported?(TestCounter, :set_name, 2)
      assert function_exported?(TestCounter, :set_name, 3)
      assert function_exported?(TestCounter, :get, 1)
      assert function_exported?(TestCounter, :get, 2)
      assert function_exported?(TestCounter, :reset, 1)
      assert function_exported?(TestCounter, :reset, 2)
    end

    test "handler implementations are callable" do
      state = %{count: 10, name: "test"}

      assert {:reply, 15, %{count: 15, name: "test"}} =
               TestCounter.handle_increment(5, state)

      assert {:reply, 7, %{count: 7, name: "test"}} =
               TestCounter.handle_decrement(3, state)

      assert {:reply, :ok, %{count: 10, name: "new-name"}} =
               TestCounter.handle_set_name("new-name", state)

      assert {:reply, ^state, ^state} = TestCounter.handle_get(state)

      assert {:noreply, %{count: 0, name: "test"}} = TestCounter.handle_reset(state)
    end
  end

  describe "full runtime integration" do
    test "client functions call DurableObject.call correctly" do
      object_id = "integration-#{System.unique_integer([:positive])}"

      # Start with increment
      {:ok, 5} = TestCounter.increment(object_id, 5)

      # Increment again
      {:ok, 10} = TestCounter.increment(object_id, 5)

      # Decrement
      {:ok, 7} = TestCounter.decrement(object_id, 3)

      # Get state - note: Server starts with empty state, not DSL defaults
      {:ok, state} = TestCounter.get(object_id)
      assert state[:count] == 7

      # Set name
      {:ok, :ok} = TestCounter.set_name(object_id, "my-counter")

      # Verify name was set
      {:ok, state} = TestCounter.get(object_id)
      assert state[:name] == "my-counter"

      # Reset
      {:ok, :noreply} = TestCounter.reset(object_id)

      # Verify reset
      {:ok, state} = TestCounter.get(object_id)
      assert state[:count] == 0

      # Cleanup
      DurableObject.stop(TestCounter, object_id)
    end
  end
end
