defmodule DurableObject.ServerTest do
  use ExUnit.Case, async: true

  alias DurableObject.Server

  defmodule TestHandler do
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
end
