defmodule DurableObject.Storage.StorageTest do
  use ExUnit.Case

  alias DurableObject.Storage
  alias DurableObject.TestRepo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)
    :ok
  end

  describe "save/5 and load/4" do
    test "saves and loads state" do
      state = %{"count" => 5, "name" => "test"}

      {:ok, _object} = Storage.save(TestRepo, "Counter", "test-1", state)
      {:ok, loaded} = Storage.load(TestRepo, "Counter", "test-1")

      assert loaded.object_type == "Counter"
      assert loaded.object_id == "test-1"
      assert loaded.state == state
    end

    test "load returns nil for non-existent object" do
      {:ok, nil} = Storage.load(TestRepo, "Counter", "nonexistent")
    end

    test "upserts on conflict" do
      {:ok, _} = Storage.save(TestRepo, "Counter", "upsert-1", %{"count" => 1})
      {:ok, _} = Storage.save(TestRepo, "Counter", "upsert-1", %{"count" => 2})

      {:ok, loaded} = Storage.load(TestRepo, "Counter", "upsert-1")
      assert loaded.state == %{"count" => 2}
    end
  end

  describe "delete/4" do
    test "deletes object" do
      {:ok, _} = Storage.save(TestRepo, "Counter", "delete-1", %{})
      {:ok, loaded} = Storage.load(TestRepo, "Counter", "delete-1")
      assert loaded != nil

      :ok = Storage.delete(TestRepo, "Counter", "delete-1")

      {:ok, nil} = Storage.load(TestRepo, "Counter", "delete-1")
    end

    test "returns :ok for non-existent object" do
      :ok = Storage.delete(TestRepo, "Counter", "nonexistent")
    end
  end
end
