defmodule DurableObject.Cluster.Local do
  @moduledoc """
  Local-mode cluster backend using Elixir's built-in Registry and DynamicSupervisor.

  This is the default backend and runs on a single node. It does not require
  any additional dependencies.
  """

  @behaviour DurableObject.Cluster.Backend

  @impl true
  def child_specs(_opts) do
    [
      {Registry, keys: :unique, name: DurableObject.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: DurableObject.ObjectSupervisor}
    ]
  end

  @impl true
  def via_tuple(module, object_id) do
    {:via, Registry, {DurableObject.Registry, {module, object_id}}}
  end

  @impl true
  def start_child(spec) do
    DynamicSupervisor.start_child(DurableObject.ObjectSupervisor, spec)
  end

  @impl true
  def count_children do
    DynamicSupervisor.count_children(DurableObject.ObjectSupervisor).active
  end
end
