defmodule DurableObject.ObjectSupervisor do
  @moduledoc """
  DynamicSupervisor for Durable Object processes.

  Objects are started with `:temporary` restart strategy since they
  will be re-created on demand when accessed.
  """
  use DynamicSupervisor

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl DynamicSupervisor
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

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

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Returns the count of currently running objects.
  """
  def count_objects do
    DynamicSupervisor.count_children(__MODULE__).active
  end
end
