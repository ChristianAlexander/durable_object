defmodule DurableObject.Cluster.Horde do
  @moduledoc """
  Horde-mode cluster backend using Horde.Registry and Horde.DynamicSupervisor.

  This backend enables DurableObject processes to be distributed across a
  cluster of Erlang nodes. It requires the `:horde` dependency to be installed.

  ## Configuration

      config :durable_object,
        registry_mode: :horde,
        cluster_opts: [
          members: :auto  # or explicit list of node names
        ]

  ## Members Configuration

  - `:auto` - Automatically includes all connected nodes plus the current node
  - `[node1, node2, ...]` - Explicit list of node names

  """

  @behaviour DurableObject.Cluster.Backend

  @impl true
  def child_specs(opts) do
    ensure_horde_available!()
    members = get_members(opts)

    [
      {Horde.Registry, name: DurableObject.HordeRegistry, keys: :unique, members: members},
      {Horde.DynamicSupervisor,
       name: DurableObject.HordeSupervisor, strategy: :one_for_one, members: members}
    ]
  end

  @impl true
  def via_tuple(module, object_id) do
    {:via, Horde.Registry, {DurableObject.HordeRegistry, {module, object_id}}}
  end

  @impl true
  def start_child(spec) do
    Horde.DynamicSupervisor.start_child(DurableObject.HordeSupervisor, spec)
  end

  @impl true
  def count_children do
    Horde.DynamicSupervisor.count_children(DurableObject.HordeSupervisor).active
  end

  defp ensure_horde_available! do
    unless Code.ensure_loaded?(Horde) do
      raise """
      Horde is not available.

      To use Horde distribution mode, add {:horde, "~> 0.9"} to your dependencies:

          defp deps do
            [
              {:durable_object, "~> 0.1"},
              {:horde, "~> 0.9"}
            ]
          end

      Then run `mix deps.get` and restart your application.
      """
    end
  end

  defp get_members(opts) do
    cluster_opts = Keyword.get(opts, :cluster_opts, [])

    case Keyword.get(cluster_opts, :members, :auto) do
      :auto ->
        # Return a function that dynamically builds member list
        # This allows Horde to track cluster membership changes
        :auto

      members when is_list(members) ->
        # Convert node names to Horde member specs
        Enum.map(members, fn node ->
          {DurableObject.HordeRegistry, node}
        end)
    end
  end
end
