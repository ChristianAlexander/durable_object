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

  Same options as `DurableObject.Server.start_link/1`.
  """
  def start_object(opts) do
    spec = %{
      id: make_ref(),
      start: {DurableObject.Server, :start_link, [opts]},
      restart: :temporary
    }

    DurableObject.Cluster.start_child(spec)
  end

  @doc """
  Returns the count of currently running objects.
  """
  def count_objects do
    DurableObject.Cluster.count_children()
  end
end
