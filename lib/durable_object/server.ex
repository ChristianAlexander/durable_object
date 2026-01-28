defmodule DurableObject.Server do
  @moduledoc """
  GenServer that backs each Durable Object instance.
  """
  use GenServer
  require Logger

  @default_hibernate_after :timer.minutes(5)

  defstruct [:module, :object_id, :state, :shutdown_after, :shutdown_timer, :repo, :prefix]

  # --- Client API ---

  @doc """
  Starts a Server process for the given module and object_id.

  ## Options

    * `:module` - The handler module (required)
    * `:object_id` - The unique identifier for this object (required)
    * `:hibernate_after` - Hibernate after this many ms of inactivity (default: 5 minutes)
    * `:shutdown_after` - Stop process after this many ms of inactivity (default: nil, no shutdown)
    * `:repo` - Ecto repo for persistence (default: nil, no persistence)
    * `:prefix` - Table prefix for multi-tenancy (default: nil)

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
    * `{:error, {:persistence_failed, reason}}` - State change could not be persisted

  """
  def call(module, object_id, handler, args \\ [], timeout \\ 5000) do
    GenServer.call(via_tuple(module, object_id), {:call, handler, args}, timeout)
  end

  @doc """
  Ensures a Durable Object is started, starting it if necessary.

  Returns `{:ok, pid}` if the object is running or was started successfully.
  Returns `{:error, reason}` if the object could not be started.

  ## Options

  Options are passed to `start_link/1` when starting a new object.
  """
  def ensure_started(module, object_id, opts \\ []) do
    case whereis(module, object_id) do
      nil ->
        start_opts = Keyword.merge(opts, module: module, object_id: object_id)
        DurableObject.ObjectSupervisor.start_object(start_opts)

      pid ->
        {:ok, pid}
    end
  end

  @doc """
  Returns the pid of a running Durable Object, or nil if not running.
  """
  def whereis(module, object_id) do
    GenServer.whereis(via_tuple(module, object_id))
  end

  @doc """
  Returns the via tuple for Registry lookup.
  """
  def via_tuple(module, object_id) do
    DurableObject.Cluster.via_tuple(module, object_id)
  end

  # --- Server Callbacks ---

  @impl GenServer
  def init(opts) do
    module = Keyword.fetch!(opts, :module)
    object_id = Keyword.fetch!(opts, :object_id)
    shutdown_after = Keyword.get(opts, :shutdown_after)
    repo = Keyword.get(opts, :repo)
    prefix = Keyword.get(opts, :prefix)
    default_state = module.__durable_object__(:default_state)

    server = %__MODULE__{
      module: module,
      object_id: object_id,
      state: default_state,
      shutdown_after: shutdown_after,
      shutdown_timer: nil,
      repo: repo,
      prefix: prefix
    }

    if repo do
      {:ok, server, {:continue, :load_state}}
    else
      {:ok, schedule_shutdown(server)}
    end
  end

  @impl GenServer
  def handle_continue(:load_state, server) do
    %{repo: repo, module: module, object_id: object_id, prefix: prefix} = server
    object_type = to_string(module)

    case DurableObject.Storage.load(repo, object_type, object_id, prefix: prefix) do
      {:ok, nil} ->
        # New object - persist default state (already set in init)
        case DurableObject.Storage.save(repo, object_type, object_id, server.state, prefix: prefix) do
          {:ok, _object} ->
            {:noreply, schedule_shutdown(server)}

          {:error, reason} ->
            Logger.error(
              "Failed to save initial state for #{object_type}:#{object_id}: #{inspect(reason)}"
            )

            {:stop, {:persistence_failed, reason}, server}
        end

      {:ok, object} ->
        {:noreply, schedule_shutdown(%{server | state: object.state})}

      {:error, reason} ->
        Logger.error("Failed to load state for #{object_type}:#{object_id}: #{inspect(reason)}")
        {:stop, {:persistence_failed, reason}, server}
    end
  end

  @impl GenServer
  def handle_call(:get_state, _from, server) do
    {:reply, server.state, schedule_shutdown(server)}
  end

  @impl GenServer
  def handle_call({:put_state, new_state}, _from, %{state: state} = server) do
    handle_state_change(server, state, new_state, :ok, nil)
  end

  @impl GenServer
  def handle_call({:call, :__fire_alarm__, [alarm_name]}, _from, server) do
    # Special handler for firing alarms from the scheduler
    %{module: module, state: state} = server

    if function_exported?(module, :handle_alarm, 2) do
      case apply(module, :handle_alarm, [alarm_name, state]) do
        {:noreply, new_state} ->
          handle_state_change(server, state, new_state, {:ok, :noreply}, nil)

        {:noreply, new_state, {:schedule_alarm, name, delay}} ->
          handle_state_change(server, state, new_state, {:ok, :noreply}, {:schedule_alarm, name, delay})

        {:error, reason} ->
          {:reply, {:error, reason}, schedule_shutdown(server)}
      end
    else
      # No alarm handler defined, just acknowledge
      {:reply, {:ok, :no_handler}, schedule_shutdown(server)}
    end
  end

  @impl GenServer
  def handle_call({:call, handler, args}, _from, server) do
    %{module: module, state: state} = server
    handler_fn = :"handle_#{handler}"

    if function_exported?(module, handler_fn, length(args) + 1) do
      case apply(module, handler_fn, args ++ [state]) do
        {:reply, result} ->
          {:reply, {:ok, result}, schedule_shutdown(server)}

        {:reply, result, new_state} ->
          handle_state_change(server, state, new_state, {:ok, result}, nil)

        {:reply, result, new_state, {:schedule_alarm, name, delay}} ->
          handle_state_change(server, state, new_state, {:ok, result}, {:schedule_alarm, name, delay})

        {:noreply, new_state} ->
          handle_state_change(server, state, new_state, {:ok, :noreply}, nil)

        {:noreply, new_state, {:schedule_alarm, name, delay}} ->
          handle_state_change(server, state, new_state, {:ok, :noreply}, {:schedule_alarm, name, delay})

        {:error, reason} ->
          {:reply, {:error, reason}, schedule_shutdown(server)}
      end
    else
      {:reply, {:error, {:unknown_handler, handler}}, schedule_shutdown(server)}
    end
  end

  @impl GenServer
  def handle_info(:shutdown_timeout, server) do
    {:stop, :normal, server}
  end

  @impl GenServer
  def terminate(_reason, _server) do
    :ok
  end

  # --- Private Functions ---

  defp handle_state_change(server, old_state, new_state, reply, alarm) do
    if new_state == old_state do
      # No state change, no persistence needed
      if alarm, do: schedule_alarm(server, elem(alarm, 1), elem(alarm, 2))
      {:reply, reply, schedule_shutdown(server)}
    else
      # State changed - persist before committing
      case persist_state(%{server | state: new_state}) do
        :ok ->
          updated_server = %{server | state: new_state}
          if alarm, do: schedule_alarm(updated_server, elem(alarm, 1), elem(alarm, 2))
          {:reply, reply, schedule_shutdown(updated_server)}

        {:error, reason} ->
          # Rollback: return error and keep old state
          {:reply, {:error, {:persistence_failed, reason}}, schedule_shutdown(server)}
      end
    end
  end

  defp persist_state(%{repo: nil}), do: :ok

  defp persist_state(server) do
    %{repo: repo, module: module, object_id: object_id, state: state, prefix: prefix} = server
    object_type = to_string(module)

    case DurableObject.Storage.save(repo, object_type, object_id, state, prefix: prefix) do
      {:ok, _object} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp schedule_shutdown(%{shutdown_after: nil} = server), do: server

  defp schedule_shutdown(%{shutdown_after: timeout, shutdown_timer: old_timer} = server) do
    if old_timer, do: Process.cancel_timer(old_timer)
    timer = Process.send_after(self(), :shutdown_timeout, timeout)
    %{server | shutdown_timer: timer}
  end

  defp schedule_alarm(%{repo: nil}, _name, _delay), do: :ok

  defp schedule_alarm(server, name, delay) do
    %{module: module, object_id: object_id, repo: repo, prefix: prefix} = server
    scheduler = Application.get_env(:durable_object, :scheduler, DurableObject.Scheduler.Polling)
    scheduler_opts = Application.get_env(:durable_object, :scheduler_opts, [])

    opts = Keyword.merge(scheduler_opts, repo: repo, prefix: prefix)
    scheduler.schedule({module, object_id}, name, delay, opts)
  end
end
