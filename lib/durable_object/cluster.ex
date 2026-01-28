defmodule DurableObject.Cluster do
  @moduledoc """
  Facade module for registry and supervisor operations.

  This module provides a unified interface for process registration and
  supervision, abstracting over the underlying backend (local or Horde).

  ## Configuration

  By default, DurableObject uses local mode which runs on a single node:

      # No configuration needed for local mode

  To enable Horde distribution across a cluster:

      config :durable_object,
        registry_mode: :horde,
        cluster_opts: [
          members: :auto  # or explicit list of node names
        ]

  ## Backend Selection

  - `:local` (default) - Uses Elixir's built-in Registry and DynamicSupervisor
  - `:horde` - Uses Horde for distributed operation (requires `:horde` dependency)

  """

  @type mode :: :local | :horde

  @doc """
  Returns the current cluster mode.

  Defaults to `:local` if not configured.
  """
  @spec mode() :: mode()
  def mode do
    Application.get_env(:durable_object, :registry_mode, :local)
  end

  @doc """
  Returns the backend module for the current mode.
  """
  @spec impl() :: module()
  if Code.ensure_loaded?(Horde) do
    def impl do
      case mode() do
        :local -> DurableObject.Cluster.Local
        :horde -> DurableObject.Cluster.Horde
      end
    end
  else
    def impl do
      case mode() do
        :local ->
          DurableObject.Cluster.Local

        :horde ->
          raise """
          Horde mode requires the :horde dependency.

          Add {:horde, "~> 0.9"} to your dependencies:

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
  end

  @doc """
  Returns child specs for the registry and supervisor.

  These specs are used by the DurableObject application supervisor.
  """
  @spec child_specs(keyword()) :: [Supervisor.child_spec()]
  def child_specs(opts \\ []) do
    cluster_opts = Application.get_env(:durable_object, :cluster_opts, [])
    impl().child_specs(Keyword.merge(cluster_opts, opts))
  end

  @doc """
  Returns a via tuple for process registration.

  Used for naming GenServer processes and looking them up.
  """
  @spec via_tuple(module(), String.t()) :: GenServer.name()
  def via_tuple(module, object_id) do
    impl().via_tuple(module, object_id)
  end

  @doc """
  Starts a child under the dynamic supervisor.
  """
  @spec start_child(Supervisor.child_spec()) ::
          {:ok, pid()} | {:ok, pid(), term()} | {:error, term()}
  def start_child(spec) do
    impl().start_child(spec)
  end

  @doc """
  Returns the count of active children in the dynamic supervisor.
  """
  @spec count_children() :: non_neg_integer()
  def count_children do
    impl().count_children()
  end
end
