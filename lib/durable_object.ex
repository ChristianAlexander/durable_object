defmodule DurableObject do
  @moduledoc """
  Durable Objects for Elixir.

  A library that provides persistent, single-instance objects that are
  accessed by ID. Each object is backed by a GenServer that:

  - Has global uniqueness per (module, object_id) pair
  - Automatically hibernates after inactivity
  - Optionally shuts down after extended inactivity
  - Dispatches calls to `handle_<name>/N` functions on the module

  ## Example

      defmodule Counter do
        def handle_increment(n \\\\ 1, state) do
          new_count = Map.get(state, :count, 0) + n
          {:reply, new_count, Map.put(state, :count, new_count)}
        end

        def handle_get(state) do
          {:reply, Map.get(state, :count, 0), state}
        end
      end

      {:ok, 1} = DurableObject.call(Counter, "test", :increment)
      {:ok, 2} = DurableObject.call(Counter, "test", :increment)
      {:ok, 2} = DurableObject.call(Counter, "test", :get)
  """

  alias DurableObject.Server

  @doc """
  Calls a handler on a Durable Object, starting it if necessary.

  Dispatches to `handle_<name>/N` function on the module, where N is
  the number of args plus one (for state).

  ## Options

    * `:hibernate_after` - Hibernate after this many ms of inactivity (default: 5 minutes)
    * `:shutdown_after` - Stop process after this many ms of inactivity (default: nil)
    * `:timeout` - Call timeout in ms (default: 5000)

  ## Returns

    * `{:ok, result}` - Handler returned `{:reply, result, new_state}`
    * `{:ok, :noreply}` - Handler returned `{:noreply, new_state}`
    * `{:error, reason}` - Handler returned `{:error, reason}` or error occurred

  ## Examples

      {:ok, 1} = DurableObject.call(Counter, "test", :increment)
      {:ok, 5} = DurableObject.call(Counter, "test", :increment, [5])
  """
  def call(module, object_id, handler, args \\ [], opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    start_opts = Keyword.drop(opts, [:timeout])

    case Server.ensure_started(module, object_id, start_opts) do
      {:ok, _pid} ->
        Server.call(module, object_id, handler, args, timeout)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the current state of a Durable Object.

  Returns the state if the object is running, or raises if not.
  To check if an object is running, use `whereis/2`.

  ## Examples

      state = DurableObject.get_state(Counter, "test")
  """
  defdelegate get_state(module, object_id), to: Server

  @doc """
  Ensures a Durable Object is started, starting it if necessary.

  Returns `{:ok, pid}` if the object is running or was started successfully.
  Returns `{:error, reason}` if the object could not be started.

  ## Options

    * `:hibernate_after` - Hibernate after this many ms of inactivity (default: 5 minutes)
    * `:shutdown_after` - Stop process after this many ms of inactivity (default: nil)

  ## Examples

      {:ok, pid} = DurableObject.ensure_started(Counter, "test")
      {:ok, ^pid} = DurableObject.ensure_started(Counter, "test")
  """
  defdelegate ensure_started(module, object_id, opts \\ []), to: Server

  @doc """
  Stops a running Durable Object.

  ## Examples

      :ok = DurableObject.stop(Counter, "test")
  """
  def stop(module, object_id, reason \\ :normal) do
    case Server.whereis(module, object_id) do
      nil -> :ok
      _pid -> GenServer.stop(Server.via_tuple(module, object_id), reason)
    end
  end

  @doc """
  Returns the pid of a running Durable Object, or nil if not running.

  ## Examples

      nil = DurableObject.whereis(Counter, "not-started")
      {:ok, _} = DurableObject.ensure_started(Counter, "test")
      pid = DurableObject.whereis(Counter, "test")
  """
  defdelegate whereis(module, object_id), to: Server
end
