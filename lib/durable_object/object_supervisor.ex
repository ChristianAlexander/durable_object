defmodule DurableObject.ObjectSupervisor do
  @moduledoc """
  Interface for Durable Object supervision.

  Objects are started with `:temporary` restart strategy since they
  will be re-created on demand when accessed.

  This module delegates to the configured cluster backend (local or Horde).
  """

  @doc """
  Starts a new Durable Object under supervision.

  ## Options

  Same options as `DurableObject.Server.start_link/1`, plus:

    * `:supervisor` - optional supervisor to use instead of the default cluster supervisor
  """
  def start_object(opts) do
    {supervisor, opts} = Keyword.pop(opts, :supervisor)

    spec = %{
      id: make_ref(),
      start: {DurableObject.Server, :start_link, [opts]},
      restart: :temporary
    }

    if supervisor do
      DynamicSupervisor.start_child(supervisor, spec)
    else
      DurableObject.Cluster.start_child(spec)
    end
  end

  @doc """
  Returns the count of currently running objects.

  ## Options

    * `:supervisor` - optional supervisor to count from instead of the default
  """
  def count_objects(opts \\ []) do
    case Keyword.get(opts, :supervisor) do
      nil -> DurableObject.Cluster.count_children()
      sup -> DynamicSupervisor.count_children(sup).active
    end
  end
end
