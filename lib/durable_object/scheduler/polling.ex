defmodule DurableObject.Scheduler.Polling do
  @moduledoc """
  Polling-based scheduler that persists alarms to the database
  and periodically checks for overdue alarms.

  This is the default scheduler implementation. It stores alarms in the
  `durable_object_alarms` table and fires them by starting the target
  object and calling `handle_alarm/2`.

  ## Configuration

      config :durable_object,
        scheduler: DurableObject.Scheduler.Polling,
        scheduler_opts: [
          repo: MyApp.Repo,
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
    [{__MODULE__.Poller, opts}]
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

      case DurableObject.call(module, object_id, :__fire_alarm__, [alarm], repo: repo, prefix: prefix) do
        {:ok, _} ->
          # Delete the alarm after successful firing
          from(a in DurableObject.Storage.Schemas.Alarm, where: a.id == ^alarm_id)
          |> repo.delete_all(prefix: prefix)

        {:error, reason} ->
          Logger.warning(
            "Failed to fire alarm #{alarm_name} for #{object_type}:#{object_id}: #{inspect(reason)}"
          )
      end
    rescue
      ArgumentError ->
        # Module or alarm atom doesn't exist, delete the stale alarm
        Logger.warning(
          "Deleting stale alarm #{alarm_name} for #{object_type}:#{object_id}: module not loaded"
        )

        from(a in DurableObject.Storage.Schemas.Alarm, where: a.id == ^alarm_id)
        |> repo.delete_all(prefix: prefix)
    end

    defp schedule_check(interval) do
      Process.send_after(self(), :check_alarms, interval)
    end
  end
end
