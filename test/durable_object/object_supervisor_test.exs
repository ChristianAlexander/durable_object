defmodule DurableObject.ObjectSupervisorTest do
  use ExUnit.Case, async: true

  alias DurableObject.{ObjectSupervisor, Server}

  defmodule TestHandler do
  end

  describe "start_object/1" do
    test "starts object under supervision" do
      {:ok, pid} = ObjectSupervisor.start_object(module: TestHandler, object_id: "sup-1")

      assert Process.alive?(pid)
      assert pid == GenServer.whereis(Server.via_tuple(TestHandler, "sup-1"))
    end

    test "object is accessible via Server API" do
      {:ok, _pid} = ObjectSupervisor.start_object(module: TestHandler, object_id: "sup-2")

      assert Server.get_state(TestHandler, "sup-2") == %{}
      assert :ok = Server.put_state(TestHandler, "sup-2", %{data: "test"})
      assert Server.get_state(TestHandler, "sup-2") == %{data: "test"}
    end

    test "returns error for duplicate object_id" do
      {:ok, _pid} = ObjectSupervisor.start_object(module: TestHandler, object_id: "sup-dup")

      assert {:error, {:already_started, _}} =
               ObjectSupervisor.start_object(module: TestHandler, object_id: "sup-dup")
    end
  end

  describe "count_objects/0" do
    test "returns count of active objects" do
      initial_count = ObjectSupervisor.count_objects()

      {:ok, _} = ObjectSupervisor.start_object(module: TestHandler, object_id: "count-1")
      {:ok, _} = ObjectSupervisor.start_object(module: TestHandler, object_id: "count-2")

      assert ObjectSupervisor.count_objects() == initial_count + 2
    end
  end
end
