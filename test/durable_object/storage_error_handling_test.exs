defmodule DurableObject.StorageErrorHandlingTest do
  use ExUnit.Case

  alias DurableObject.Storage
  alias DurableObject.TestRepo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)
    :ok
  end

  describe "telemetry events" do
    setup do
      ref = make_ref()
      test_pid = self()

      events = [
        [:durable_object, :storage, :save, :start],
        [:durable_object, :storage, :save, :stop],
        [:durable_object, :storage, :load, :start],
        [:durable_object, :storage, :load, :stop],
        [:durable_object, :storage, :delete, :start],
        [:durable_object, :storage, :delete, :stop]
      ]

      :telemetry.attach_many(
        "test-storage-#{inspect(ref)}",
        events,
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach("test-storage-#{inspect(ref)}")
      end)

      :ok
    end

    test "save emits start and stop events" do
      {:ok, _} = Storage.save(TestRepo, "Counter", "telemetry-save-1", %{count: 1})

      assert_receive {:telemetry_event, [:durable_object, :storage, :save, :start], %{system_time: _}, metadata}
      assert metadata.repo == TestRepo
      assert metadata.object_type == "Counter"
      assert metadata.object_id == "telemetry-save-1"

      assert_receive {:telemetry_event, [:durable_object, :storage, :save, :stop], %{duration: duration}, _}
      assert duration > 0
    end

    test "load emits start and stop events" do
      {:ok, _} = Storage.save(TestRepo, "Counter", "telemetry-load-1", %{})
      {:ok, _} = Storage.load(TestRepo, "Counter", "telemetry-load-1")

      # Clear save events
      assert_receive {:telemetry_event, [:durable_object, :storage, :save, :start], _, _}
      assert_receive {:telemetry_event, [:durable_object, :storage, :save, :stop], _, _}

      assert_receive {:telemetry_event, [:durable_object, :storage, :load, :start], %{system_time: _}, metadata}
      assert metadata.repo == TestRepo
      assert metadata.object_type == "Counter"
      assert metadata.object_id == "telemetry-load-1"

      assert_receive {:telemetry_event, [:durable_object, :storage, :load, :stop], %{duration: duration}, _}
      assert duration > 0
    end

    test "delete emits start and stop events" do
      {:ok, _} = Storage.save(TestRepo, "Counter", "telemetry-delete-1", %{})
      :ok = Storage.delete(TestRepo, "Counter", "telemetry-delete-1")

      # Clear save events
      assert_receive {:telemetry_event, [:durable_object, :storage, :save, :start], _, _}
      assert_receive {:telemetry_event, [:durable_object, :storage, :save, :stop], _, _}

      assert_receive {:telemetry_event, [:durable_object, :storage, :delete, :start], %{system_time: _}, metadata}
      assert metadata.repo == TestRepo
      assert metadata.object_type == "Counter"
      assert metadata.object_id == "telemetry-delete-1"

      assert_receive {:telemetry_event, [:durable_object, :storage, :delete, :stop], %{duration: _}, _}
    end
  end

  describe "return values" do
    test "save returns {:ok, object} on success" do
      result = Storage.save(TestRepo, "Counter", "return-save-1", %{count: 5})

      assert {:ok, object} = result
      assert object.object_type == "Counter"
      assert object.object_id == "return-save-1"
      assert object.state == %{count: 5}
    end

    test "load returns {:ok, object} when found" do
      {:ok, _} = Storage.save(TestRepo, "Counter", "return-load-1", %{"count" => 10})
      result = Storage.load(TestRepo, "Counter", "return-load-1")

      assert {:ok, object} = result
      assert object.object_type == "Counter"
      assert object.object_id == "return-load-1"
      assert object.state == %{"count" => 10}
    end

    test "load returns {:ok, nil} when not found" do
      result = Storage.load(TestRepo, "Counter", "nonexistent-123")
      assert {:ok, nil} = result
    end

    test "delete returns :ok on success" do
      {:ok, _} = Storage.save(TestRepo, "Counter", "return-delete-1", %{})
      result = Storage.delete(TestRepo, "Counter", "return-delete-1")
      assert :ok = result

      # Verify it's actually deleted
      {:ok, nil} = Storage.load(TestRepo, "Counter", "return-delete-1")
    end

    test "delete returns :ok for non-existent object" do
      result = Storage.delete(TestRepo, "Counter", "nonexistent-789")
      assert :ok = result
    end
  end
end
