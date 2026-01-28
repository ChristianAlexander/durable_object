defmodule DurableObject.Scheduler.Polling do
  @moduledoc """
  Polling-based scheduler that persists alarms to the database
  and periodically checks for overdue alarms.

  This is the default scheduler implementation. It stores alarms in the
  `durable_object_alarms` table and fires them by starting the target
  object and calling `handle_alarm/2`.

  ## Configuration

      config :durable_object,
        repo: MyApp.Repo,
        scheduler: DurableObject.Scheduler.Polling,
        scheduler_opts: [
          polling_interval: :timer.seconds(30)
        ]

  """

  @behaviour DurableObject.Scheduler

  import Ecto.Query
  alias DurableObject.Storage.Schemas.Alarm

  # --- Behaviour Implementation ---

  @impl DurableObject.Scheduler
  def schedule({module, object_id}, alarm_name, delay_ms, opts) do
    repo = Keyword.fetch!(opts, :repo)
    prefix = Keyword.get(opts, :prefix)
    scheduled_at = DateTime.add(DateTime.utc_now(), delay_ms, :millisecond)

    attrs = %{
      object_type: to_string(module),
      object_id: object_id,
      alarm_name: to_string(alarm_name),
      scheduled_at: scheduled_at
    }

    case repo.insert(
           Alarm.changeset(%Alarm{}, attrs),
           on_conflict: [set: [scheduled_at: scheduled_at, updated_at: DateTime.utc_now()]],
           conflict_target: [:object_type, :object_id, :alarm_name],
           prefix: prefix
         ) do
      {:ok, _alarm} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl DurableObject.Scheduler
  def cancel({module, object_id}, alarm_name, opts) do
    repo = Keyword.fetch!(opts, :repo)
    prefix = Keyword.get(opts, :prefix)

    from(a in Alarm,
      where: a.object_type == ^to_string(module),
      where: a.object_id == ^object_id,
      where: a.alarm_name == ^to_string(alarm_name)
    )
    |> repo.delete_all(prefix: prefix)

    :ok
  end

  @impl DurableObject.Scheduler
  def cancel_all({module, object_id}, opts) do
    repo = Keyword.fetch!(opts, :repo)
    prefix = Keyword.get(opts, :prefix)

    from(a in Alarm,
      where: a.object_type == ^to_string(module),
      where: a.object_id == ^object_id
    )
    |> repo.delete_all(prefix: prefix)

    :ok
  end

  @impl DurableObject.Scheduler
  def list({module, object_id}, opts) do
    repo = Keyword.fetch!(opts, :repo)
    prefix = Keyword.get(opts, :prefix)

    alarms =
      from(a in Alarm,
        where: a.object_type == ^to_string(module),
        where: a.object_id == ^object_id,
        select: {a.alarm_name, a.scheduled_at},
        order_by: [asc: a.scheduled_at]
      )
      |> repo.all(prefix: prefix)
      |> Enum.map(fn {name, scheduled_at} ->
        {String.to_atom(name), scheduled_at}
      end)

    {:ok, alarms}
  end

  @impl DurableObject.Scheduler
  def child_spec(opts) do
    case DurableObject.Cluster.mode() do
      :local ->
        [{__MODULE__.Poller, opts}]

      :horde ->
        [
          {DurableObject.Singleton,
           name: __MODULE__.Poller, child_module: __MODULE__.Poller, child_opts: opts}
        ]
    end
  end

  # --- Poller GenServer ---

  defmodule Poller do
    @moduledoc false
    use GenServer
    import Ecto.Query
    require Logger

    @default_polling_interval :timer.seconds(30)

    def start_link(opts) do
      name = Keyword.get(opts, :name, __MODULE__)
      GenServer.start_link(__MODULE__, opts, name: name)
    end

    @impl GenServer
    def init(opts) do
      interval = Keyword.get(opts, :polling_interval, @default_polling_interval)
      repo = Keyword.get(opts, :repo)
      prefix = Keyword.get(opts, :prefix)

      state = %{repo: repo, prefix: prefix, interval: interval}

      # Only start polling if repo is configured
      if repo do
        schedule_check(interval)
      end

      {:ok, state}
    end

    @impl GenServer
    def handle_info(:check_alarms, %{repo: nil} = state) do
      # No repo configured, don't poll
      {:noreply, state}
    end

    @impl GenServer
    def handle_info(:check_alarms, state) do
      fire_overdue_alarms(state)
      schedule_check(state.interval)
      {:noreply, state}
    end

    defp fire_overdue_alarms(%{repo: repo, prefix: prefix}) do
      now = DateTime.utc_now()

      query =
        from(a in DurableObject.Storage.Schemas.Alarm,
          where: a.scheduled_at <= ^now,
          select: {a.object_type, a.object_id, a.alarm_name, a.id}
        )

      repo.all(query, prefix: prefix)
      |> Enum.each(fn {object_type, object_id, alarm_name, alarm_id} ->
        fire_alarm(repo, prefix, object_type, object_id, alarm_name, alarm_id)
      end)
    end

    defp fire_alarm(repo, prefix, object_type, object_id, alarm_name, alarm_id) do
      module = String.to_existing_atom(object_type)
      alarm = String.to_existing_atom(alarm_name)

      # Delete the alarm BEFORE firing so that if the handler schedules a new
      # alarm with the same name, the upsert creates a fresh record that won't
      # be deleted after we return.
      delete_alarm(repo, prefix, alarm_id)

      case DurableObject.call(module, object_id, :__fire_alarm__, [alarm],
             repo: repo,
             prefix: prefix
           ) do
        {:ok, _} ->
          :ok

        {:error, {:persistence_failed, reason}} ->
          Logger.warning(
            "Alarm #{alarm_name} for #{object_type}:#{object_id} fired but persistence failed: #{inspect(reason)}"
          )

        {:error, reason} ->
          Logger.warning(
            "Failed to fire alarm #{alarm_name} for #{object_type}:#{object_id}: #{inspect(reason)}"
          )
      end
    rescue
      ArgumentError ->
        # Module or alarm atom doesn't exist - alarm already deleted above
        Logger.warning("Alarm #{alarm_name} for #{object_type}:#{object_id}: module not loaded")
    end

    defp delete_alarm(repo, prefix, alarm_id) do
      from(a in DurableObject.Storage.Schemas.Alarm, where: a.id == ^alarm_id)
      |> repo.delete_all(prefix: prefix)
    rescue
      exception ->
        Logger.error("Failed to delete alarm #{alarm_id}: #{Exception.message(exception)}")
    end

    defp schedule_check(interval) do
      Process.send_after(self(), :check_alarms, interval)
    end
  end
end
