defmodule DurableObject.ClusterTest do
  use ExUnit.Case, async: true

  alias DurableObject.Cluster
  alias DurableObject.Cluster.Local
  alias DurableObject.Cluster.Horde, as: HordeBackend

  describe "mode/0" do
    test "defaults to :local" do
      # Clear any configured mode
      original = Application.get_env(:durable_object, :registry_mode)
      Application.delete_env(:durable_object, :registry_mode)

      try do
        assert Cluster.mode() == :local
      after
        if original, do: Application.put_env(:durable_object, :registry_mode, original)
      end
    end

    test "returns configured mode" do
      original = Application.get_env(:durable_object, :registry_mode)

      try do
        Application.put_env(:durable_object, :registry_mode, :horde)
        assert Cluster.mode() == :horde

        Application.put_env(:durable_object, :registry_mode, :local)
        assert Cluster.mode() == :local
      after
        if original do
          Application.put_env(:durable_object, :registry_mode, original)
        else
          Application.delete_env(:durable_object, :registry_mode)
        end
      end
    end
  end

  describe "impl/0" do
    test "returns Local for local mode" do
      original = Application.get_env(:durable_object, :registry_mode)
      Application.delete_env(:durable_object, :registry_mode)

      try do
        assert Cluster.impl() == Local
      after
        if original, do: Application.put_env(:durable_object, :registry_mode, original)
      end
    end

    test "returns Horde for horde mode" do
      original = Application.get_env(:durable_object, :registry_mode)

      try do
        Application.put_env(:durable_object, :registry_mode, :horde)
        assert Cluster.impl() == HordeBackend
      after
        if original do
          Application.put_env(:durable_object, :registry_mode, original)
        else
          Application.delete_env(:durable_object, :registry_mode)
        end
      end
    end
  end

  describe "Local backend" do
    test "generates correct via_tuple" do
      via = Local.via_tuple(MyModule, "object-123")
      assert {:via, Registry, {DurableObject.Registry, {MyModule, "object-123"}}} = via
    end

    test "generates correct child_specs" do
      specs = Local.child_specs([])

      assert length(specs) == 2

      # Check Registry spec
      registry_spec =
        Enum.find(specs, fn spec ->
          case spec do
            {Registry, _opts} -> true
            _ -> false
          end
        end)

      assert {Registry, opts} = registry_spec
      assert Keyword.get(opts, :keys) == :unique
      assert Keyword.get(opts, :name) == DurableObject.Registry

      # Check DynamicSupervisor spec
      supervisor_spec =
        Enum.find(specs, fn spec ->
          case spec do
            {DynamicSupervisor, _opts} -> true
            _ -> false
          end
        end)

      assert {DynamicSupervisor, opts} = supervisor_spec
      assert Keyword.get(opts, :strategy) == :one_for_one
      assert Keyword.get(opts, :name) == DurableObject.ObjectSupervisor
    end
  end

  describe "Horde backend" do
    test "generates correct via_tuple format" do
      # This doesn't require Horde to be installed since it just builds a tuple
      via = HordeBackend.via_tuple(MyModule, "object-123")
      assert {:via, Horde.Registry, {DurableObject.HordeRegistry, {MyModule, "object-123"}}} = via
    end
  end

  describe "integration with ObjectSupervisor" do
    test "start_object works through Cluster abstraction" do
      # Start an object through the supervisor
      opts = [module: TestCounter, object_id: "cluster-test-#{System.unique_integer()}"]
      assert {:ok, pid} = DurableObject.ObjectSupervisor.start_object(opts)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "count_objects works through Cluster abstraction" do
      # Get initial count
      initial_count = DurableObject.ObjectSupervisor.count_objects()
      assert is_integer(initial_count)
      assert initial_count >= 0

      # Start an object and verify count increased
      opts = [module: TestCounter, object_id: "cluster-count-#{System.unique_integer()}"]
      {:ok, _pid} = DurableObject.ObjectSupervisor.start_object(opts)

      new_count = DurableObject.ObjectSupervisor.count_objects()
      assert new_count == initial_count + 1
    end
  end
end
