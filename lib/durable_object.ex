defmodule DurableObject do
  @moduledoc """
  Durable Objects for Elixir.

  A library that provides persistent, single-instance objects that are
  accessed by ID. Each object is backed by a GenServer that:

  - Has global uniqueness per (module, object_id) pair
  - Automatically hibernates after inactivity
  - Optionally shuts down after extended inactivity
  - Dispatches calls to `handle_<name>/N` functions on the module

  ## Using the DSL

  The recommended way to define Durable Objects is with the Spark DSL:

      defmodule MyApp.Counter do
        use DurableObject

        state do
          field :count, :integer, default: 0
        end

        handlers do
          handler :increment, args: [:amount]
          handler :get
        end

        options do
          hibernate_after 300_000
        end

        @impl DurableObject.Behaviour
        def handle_increment(amount, state) do
          new_count = state.count + amount
          {:reply, new_count, %{state | count: new_count}}
        end

        @impl DurableObject.Behaviour
        def handle_get(state) do
          {:reply, state.count, state}
        end
      end

  The DSL generates client API functions automatically:

      {:ok, count} = MyApp.Counter.increment("user-123", 5)
      {:ok, count} = MyApp.Counter.get("user-123")

  ## Manual Usage (without DSL)

  You can also call Durable Objects directly without the DSL:

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
  Use DurableObject to define a Durable Object with the Spark DSL.

  This enables the declarative DSL for defining state fields, handlers,
  and lifecycle options.

  ## Example

      defmodule MyApp.Counter do
        use DurableObject

        state do
          field :count, :integer, default: 0
        end

        handlers do
          handler :increment, args: [:amount]
          handler :get
        end

        @impl DurableObject.Behaviour
        def handle_increment(amount, state) do
          new_count = state.count + amount
          {:reply, new_count, %{state | count: new_count}}
        end

        @impl DurableObject.Behaviour
        def handle_get(state) do
          {:reply, state.count, state}
        end
      end
  """
  defmacro __using__(_opts) do
    quote do
      use DurableObject.Dsl
      @behaviour DurableObject.Behaviour
    end
  end

  @doc """
  Calls a handler on a Durable Object, starting it if necessary.

  Dispatches to `handle_<name>/N` function on the module, where N is
  the number of args plus one (for state).

  ## Options

    * `:repo` - Ecto repo for persistence (default: configured or nil)
    * `:prefix` - Table prefix for multi-tenancy (default: nil)
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

      # With persistence
      {:ok, 1} = DurableObject.call(Counter, "test", :increment, [], repo: MyApp.Repo)
  """
  def call(module, object_id, handler, args \\ [], opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    start_opts = opts |> Keyword.drop([:timeout]) |> merge_default_repo()

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

    * `:repo` - Ecto repo for persistence (default: configured or nil)
    * `:prefix` - Table prefix for multi-tenancy (default: nil)
    * `:hibernate_after` - Hibernate after this many ms of inactivity (default: 5 minutes)
    * `:shutdown_after` - Stop process after this many ms of inactivity (default: nil)

  ## Examples

      {:ok, pid} = DurableObject.ensure_started(Counter, "test")
      {:ok, ^pid} = DurableObject.ensure_started(Counter, "test")
  """
  def ensure_started(module, object_id, opts \\ []) do
    opts = merge_default_repo(opts)
    Server.ensure_started(module, object_id, opts)
  end

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

  @doc """
  Returns the configured default repo, or nil if not configured.

  Configure in your application config:

      config :durable_object, repo: MyApp.Repo
  """
  def default_repo do
    Application.get_env(:durable_object, :repo)
  end

  @doc """
  Schedules an alarm to fire after `delay_ms` milliseconds.

  When the alarm fires, `handle_alarm(alarm_name, state)` will be called on
  the object's module. If no `handle_alarm/2` is defined, the alarm is
  silently acknowledged.

  ## Options

    * `:repo` - Ecto repo for persistence (default: configured or nil)
    * `:prefix` - Table prefix for multi-tenancy (default: nil)

  ## Examples

      # Schedule an alarm to fire in 1 hour
      :ok = DurableObject.schedule_alarm(Counter, "user-123", :cleanup, :timer.hours(1))

  ## Handler

  Define `handle_alarm/2` in your module:

      def handle_alarm(:cleanup, state) do
        # Do cleanup
        {:noreply, state}
      end

      def handle_alarm(:daily_reset, state) do
        # Reset and reschedule
        {:noreply, %{state | count: 0}, {:schedule_alarm, :daily_reset, :timer.hours(24)}}
      end
  """
  def schedule_alarm(module, object_id, alarm_name, delay_ms, opts \\ []) do
    opts = merge_default_repo(opts)
    scheduler = Application.get_env(:durable_object, :scheduler, DurableObject.Scheduler.Polling)
    scheduler_opts = Application.get_env(:durable_object, :scheduler_opts, [])

    merged_opts = Keyword.merge(scheduler_opts, opts)
    scheduler.schedule({module, object_id}, alarm_name, delay_ms, merged_opts)
  end

  @doc """
  Cancels a pending alarm.

  Returns `:ok` even if the alarm doesn't exist.

  ## Options

    * `:repo` - Ecto repo for persistence (default: configured or nil)
    * `:prefix` - Table prefix for multi-tenancy (default: nil)

  ## Examples

      :ok = DurableObject.cancel_alarm(Counter, "user-123", :cleanup)
  """
  def cancel_alarm(module, object_id, alarm_name, opts \\ []) do
    opts = merge_default_repo(opts)
    scheduler = Application.get_env(:durable_object, :scheduler, DurableObject.Scheduler.Polling)
    scheduler_opts = Application.get_env(:durable_object, :scheduler_opts, [])

    merged_opts = Keyword.merge(scheduler_opts, opts)
    scheduler.cancel({module, object_id}, alarm_name, merged_opts)
  end

  @doc """
  Cancels all pending alarms for an object.

  ## Options

    * `:repo` - Ecto repo for persistence (default: configured or nil)
    * `:prefix` - Table prefix for multi-tenancy (default: nil)

  ## Examples

      :ok = DurableObject.cancel_all_alarms(Counter, "user-123")
  """
  def cancel_all_alarms(module, object_id, opts \\ []) do
    opts = merge_default_repo(opts)
    scheduler = Application.get_env(:durable_object, :scheduler, DurableObject.Scheduler.Polling)
    scheduler_opts = Application.get_env(:durable_object, :scheduler_opts, [])

    merged_opts = Keyword.merge(scheduler_opts, opts)
    scheduler.cancel_all({module, object_id}, merged_opts)
  end

  @doc """
  Lists all pending alarms for an object.

  Returns a list of `{alarm_name, scheduled_at}` tuples, ordered by scheduled time.

  ## Options

    * `:repo` - Ecto repo for persistence (default: configured or nil)
    * `:prefix` - Table prefix for multi-tenancy (default: nil)

  ## Examples

      {:ok, alarms} = DurableObject.list_alarms(Counter, "user-123")
      # => [{:cleanup, ~U[2024-01-15 10:30:00Z]}, {:daily_reset, ~U[2024-01-16 00:00:00Z]}]
  """
  def list_alarms(module, object_id, opts \\ []) do
    opts = merge_default_repo(opts)
    scheduler = Application.get_env(:durable_object, :scheduler, DurableObject.Scheduler.Polling)
    scheduler_opts = Application.get_env(:durable_object, :scheduler_opts, [])

    merged_opts = Keyword.merge(scheduler_opts, opts)
    scheduler.list({module, object_id}, merged_opts)
  end

  # --- Private Functions ---

  defp merge_default_repo(opts) do
    case Keyword.get(opts, :repo) do
      nil ->
        case default_repo() do
          nil -> opts
          repo -> Keyword.put(opts, :repo, repo)
        end

      _repo ->
        opts
    end
  end
end
