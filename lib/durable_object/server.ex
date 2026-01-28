defmodule DurableObject.Server do
  @moduledoc """
  GenServer that backs each Durable Object instance.
  """
  use GenServer

  @default_hibernate_after :timer.minutes(5)

  defstruct [:module, :object_id, :state]

  # --- Client API ---

  @doc """
  Starts a Server process for the given module and object_id.

  ## Options

    * `:module` - The handler module (required)
    * `:object_id` - The unique identifier for this object (required)
    * `:hibernate_after` - Hibernate after this many ms of inactivity (default: 5 minutes)

  """
  def start_link(opts) do
    module = Keyword.fetch!(opts, :module)
    object_id = Keyword.fetch!(opts, :object_id)
    hibernate_after = Keyword.get(opts, :hibernate_after, @default_hibernate_after)

    GenServer.start_link(__MODULE__, opts,
      name: via_tuple(module, object_id),
      hibernate_after: hibernate_after
    )
  end

  @doc """
  Returns the default hibernate_after value in milliseconds.
  """
  def default_hibernate_after, do: @default_hibernate_after

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
  Calls a handler on a Durable Object.

  Dispatches to `handle_<name>/N` function on the module, where N is
  the number of args plus one (for state).

  ## Returns

    * `{:ok, result}` - Handler returned `{:reply, result, new_state}`
    * `{:ok, :noreply}` - Handler returned `{:noreply, new_state}`
    * `{:error, reason}` - Handler returned `{:error, reason}` or handler not found

  """
  def call(module, object_id, handler, args \\ [], timeout \\ 5000) do
    GenServer.call(via_tuple(module, object_id), {:call, handler, args}, timeout)
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

  @impl GenServer
  def handle_call({:call, handler, args}, _from, server) do
    %{module: module, state: state} = server
    handler_fn = :"handle_#{handler}"

    if function_exported?(module, handler_fn, length(args) + 1) do
      case apply(module, handler_fn, args ++ [state]) do
        {:reply, result, new_state} ->
          {:reply, {:ok, result}, %{server | state: new_state}}

        {:noreply, new_state} ->
          {:reply, {:ok, :noreply}, %{server | state: new_state}}

        {:error, reason} ->
          {:reply, {:error, reason}, server}
      end
    else
      {:reply, {:error, {:unknown_handler, handler}}, server}
    end
  end
end
