defmodule DurableObject.Singleton do
  @moduledoc """
  Cluster singleton utility for ensuring only one instance of a process
  runs across the cluster when using Horde mode.

  This is used internally to run the Poller process as a singleton when
  DurableObject is configured for Horde distribution.

  ## Usage

      # In your supervision tree
      {DurableObject.Singleton,
        name: MyApp.Poller,
        child_module: MyApp.Poller,
        child_opts: [repo: MyApp.Repo]}

  The singleton registers itself with Horde.Registry to ensure only one
  instance runs across the cluster. If the node hosting the singleton goes
  down, Horde will automatically start a new instance on another node.
  """

  use GenServer

  @doc """
  Starts the singleton wrapper.

  ## Options

  - `:name` - The name to register the singleton under (required)
  - `:child_module` - The module to start as the singleton (required)
  - `:child_opts` - Options to pass to the child module's start_link (default: [])

  """
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(name))
  end

  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{
      id: {__MODULE__, name},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  defp via_tuple(name) do
    {:via, Horde.Registry, {DurableObject.HordeRegistry, {__MODULE__, name}}}
  end

  @impl GenServer
  def init(opts) do
    child_module = Keyword.fetch!(opts, :child_module)
    child_opts = Keyword.get(opts, :child_opts, [])

    # Start the actual child process
    case child_module.start_link(Keyword.put(child_opts, :name, nil)) do
      {:ok, pid} ->
        Process.monitor(pid)
        {:ok, %{child_pid: pid, child_module: child_module, child_opts: child_opts}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{child_pid: pid} = state) do
    # Child process died, stop the singleton so Horde can restart it
    {:stop, reason, state}
  end

  @impl GenServer
  def terminate(_reason, %{child_pid: pid}) do
    # Stop the child process when the singleton stops
    if Process.alive?(pid) do
      Process.exit(pid, :shutdown)
    end

    :ok
  end
end
