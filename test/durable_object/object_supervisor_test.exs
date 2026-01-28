defmodule DurableObject.ObjectSupervisorTest do
  use ExUnit.Case, async: true

  alias DurableObject.{ObjectSupervisor, Server}
  import DurableObject.TestHelpers

  defmodule TestHandler do
    use DurableObject

    state do
      field(:data, :string, default: nil)
    end

    handlers do
      handler(:get)
    end

    def handle_get(state) do
      {:reply, state, state}
    end
  end

  describe "start_object/1" do
    test "starts object under supervision" do
      id = unique_id("sup")
      {:ok, pid} = ObjectSupervisor.start_object(module: TestHandler, object_id: id)

      assert Process.alive?(pid)
      assert pid == GenServer.whereis(Server.via_tuple(TestHandler, id))
    end

    test "object is accessible via Server API" do
      id = unique_id("sup")
      {:ok, _pid} = ObjectSupervisor.start_object(module: TestHandler, object_id: id)

      state = Server.get_state(TestHandler, id)
      assert state.data == nil

      assert :ok = Server.put_state(TestHandler, id, %{data: "test"})
      assert Server.get_state(TestHandler, id) == %{data: "test"}
    end

    test "returns error for duplicate object_id" do
      id = unique_id("sup")
      {:ok, _pid} = ObjectSupervisor.start_object(module: TestHandler, object_id: id)

      assert {:error, {:already_started, _}} =
               ObjectSupervisor.start_object(module: TestHandler, object_id: id)
    end
  end

  describe "count_objects/1" do
    test "returns count of active objects" do
      {:ok, sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

      assert ObjectSupervisor.count_objects(supervisor: sup) == 0

      {:ok, _} =
        ObjectSupervisor.start_object(
          module: TestHandler,
          object_id: unique_id("count"),
          supervisor: sup
        )

      {:ok, _} =
        ObjectSupervisor.start_object(
          module: TestHandler,
          object_id: unique_id("count"),
          supervisor: sup
        )

      assert ObjectSupervisor.count_objects(supervisor: sup) == 2
    end
  end
end
