defmodule DurableObject.StateIdTest do
  use ExUnit.Case

  alias DurableObject.{Server, Storage, TestRepo}
  import DurableObject.TestHelpers

  defmodule IdCounter do
    use DurableObject

    state do
      field(:count, :integer, default: 0)
    end

    handlers do
      handler(:get_id)
      handler(:increment)
    end

    def handle_get_id(state) do
      {:reply, state.id, state}
    end

    def handle_increment(state) do
      new_count = state.count + 1
      {:reply, new_count, %{state | count: new_count}}
    end
  end

  defmodule IdAfterLoad do
    use DurableObject

    state do
      field(:loaded_id, :string, default: nil)
    end

    handlers do
      handler(:get)
    end

    def after_load(state) do
      {:ok, %{state | loaded_id: state.id}}
    end

    def handle_get(state) do
      {:reply, state, state}
    end
  end

  describe "state.id in handlers (no persistence)" do
    test "state.id is set to the object_id" do
      id = unique_id("id")
      {:ok, _pid} = Server.start_link(module: IdCounter, object_id: id)

      assert {:ok, ^id} = Server.call(IdCounter, id, :get_id)
    end

    test "state.id persists across handler calls" do
      id = unique_id("id")
      {:ok, _pid} = Server.start_link(module: IdCounter, object_id: id)

      Server.call(IdCounter, id, :increment)
      Server.call(IdCounter, id, :increment)

      assert {:ok, ^id} = Server.call(IdCounter, id, :get_id)
    end
  end

  describe "state.id with persistence" do
    setup do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)
      Ecto.Adapters.SQL.Sandbox.mode(TestRepo, {:shared, self()})
      :ok
    end

    test "state.id is available in handler with repo" do
      id = unique_id("id-persist")

      {:ok, _pid} =
        Server.start_link(module: IdCounter, object_id: id, repo: TestRepo)

      assert {:ok, ^id} = Server.call(IdCounter, id, :get_id)
    end

    test "id is NOT persisted to the database" do
      id = unique_id("id-not-stored")

      {:ok, _pid} =
        Server.start_link(module: IdCounter, object_id: id, repo: TestRepo)

      Server.call(IdCounter, id, :increment)

      {:ok, object} = Storage.load(TestRepo, "#{IdCounter}", id)
      refute Map.has_key?(object.state, "id")
      refute Map.has_key?(object.state, :id)
      assert Map.has_key?(object.state, "count")
    end

    test "state.id survives reload from database" do
      id = unique_id("id-reload")

      # Start, increment, stop
      {:ok, pid} =
        Server.start_link(module: IdCounter, object_id: id, repo: TestRepo)

      Server.call(IdCounter, id, :increment)
      GenServer.stop(pid)

      # Restart - id should be set again
      {:ok, _pid} =
        Server.start_link(module: IdCounter, object_id: id, repo: TestRepo)

      assert {:ok, ^id} = Server.call(IdCounter, id, :get_id)
    end

    test "state.id is available in after_load" do
      id = unique_id("id-after-load")

      {:ok, _pid} =
        Server.start_link(module: IdAfterLoad, object_id: id, repo: TestRepo)

      {:ok, state} = Server.call(IdAfterLoad, id, :get)
      assert state.loaded_id == id
      assert state.id == id
    end
  end

  describe "compile-time validation" do
    test "declaring field :id raises a compile error" do
      output =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          defmodule ReservedIdField do
            use DurableObject.Dsl

            state do
              field(:id, :string)
            end

            handlers do
              handler(:get)
            end

            def handle_get(state), do: {:reply, state, state}
          end
        end)

      assert output =~ "reserved"
    end
  end

  describe "State struct" do
    test "State struct includes :id field with nil default" do
      state = %IdCounter.State{}
      assert Map.has_key?(state, :id)
      assert state.id == nil
    end

    test "default_state includes :id field" do
      default = IdCounter.__durable_object__(:default_state)
      assert Map.has_key?(default, :id)
      assert default.id == nil
    end
  end
end
