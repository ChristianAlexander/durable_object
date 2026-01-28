defmodule DurableObject.Cluster.Backend do
  @moduledoc """
  Behaviour definition for cluster backend implementations.

  A backend provides the registry and supervisor infrastructure for
  DurableObject processes. Two implementations are provided:

  - `DurableObject.Cluster.Local` - Uses Elixir's built-in Registry and DynamicSupervisor
  - `DurableObject.Cluster.Horde` - Uses Horde for distributed operation across a cluster

  """

  @doc """
  Returns the child specs for the registry and supervisor.

  These specs are added to the DurableObject application supervisor.
  """
  @callback child_specs(opts :: keyword()) :: [Supervisor.child_spec()]

  @doc """
  Returns a via tuple for process registration.

  The tuple is used with GenServer.start_link's `:name` option and
  can be used to look up processes by module and object_id.
  """
  @callback via_tuple(module :: module(), object_id :: String.t()) :: GenServer.name()

  @doc """
  Starts a child under the dynamic supervisor.

  Returns `{:ok, pid}` on success or `{:error, reason}` on failure.
  """
  @callback start_child(spec :: Supervisor.child_spec()) ::
              {:ok, pid()} | {:ok, pid(), term()} | {:error, term()}

  @doc """
  Returns the count of active children in the dynamic supervisor.
  """
  @callback count_children() :: non_neg_integer()
end
