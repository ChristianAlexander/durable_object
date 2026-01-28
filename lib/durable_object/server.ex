defmodule DurableObject.Server do
  @moduledoc """
  GenServer that backs each Durable Object instance.
  """
  use GenServer

  defstruct [:module, :object_id, :state]

  # --- Client API ---

  @doc """
  Starts a Server process for the given module and object_id.

  ## Options

    * `:module` - The handler module (required)
    * `:object_id` - The unique identifier for this object (required)

  """
  def start_link(opts) do
    module = Keyword.fetch!(opts, :module)
    object_id = Keyword.fetch!(opts, :object_id)

    GenServer.start_link(__MODULE__, opts, name: via_tuple(module, object_id))
  end

  @doc """
  Gets the current state of a Durable Object.
  """
  def get_state(module, object_id) do
    GenServer.call(via_tuple(module, object_id), :get_state)
  end

  @doc """
  Puts a new state for a Durable Object.
  """
  def put_state(module, object_id, new_state) do
    GenServer.call(via_tuple(module, object_id), {:put_state, new_state})
  end

  @doc """
  Returns the via tuple for Registry lookup.
  """
  def via_tuple(module, object_id) do
    {:via, Registry, {DurableObject.Registry, {module, object_id}}}
  end

  # --- Server Callbacks ---

  @impl GenServer
  def init(opts) do
    module = Keyword.fetch!(opts, :module)
    object_id = Keyword.fetch!(opts, :object_id)

    {:ok, %__MODULE__{module: module, object_id: object_id, state: %{}}}
  end

  @impl GenServer
  def handle_call(:get_state, _from, server) do
    {:reply, server.state, server}
  end

  @impl GenServer
  def handle_call({:put_state, new_state}, _from, server) do
    {:reply, :ok, %{server | state: new_state}}
  end
end
