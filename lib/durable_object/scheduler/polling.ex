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
          polling_interval: :timer.seconds(30),
          claim_ttl: :timer.seconds(60)
        ]

  ## Options

    * `:polling_interval` - How often to check for overdue alarms (default: 30 seconds)
    * `:claim_ttl` - How long a claimed alarm waits before being retried (default: 60 seconds)

  ## Crash Recovery

  The polling scheduler uses claim-based execution for crash recovery:

  1. **Claim**: Before firing, the scheduler atomically sets `claimed_at` on the alarm
  2. **Fire**: The object's `handle_alarm/2` callback is invoked
  3. **Delete**: On success, the alarm is deleted only if still claimed

  If a handler reschedules the same alarm, the upsert clears `claimed_at`, so the
  delete becomes a no-op and the new alarm persists. If the handler fails or the
  server crashes, the alarm remains claimed and will be retried after `claim_ttl`
  expires.

  This provides **at-least-once delivery** semantics. Handlers should be idempotent.
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
           on_conflict: [
             set: [scheduled_at: scheduled_at, claimed_at: nil, updated_at: DateTime.utc_now()]
           ],
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
    @default_claim_ttl_ms :timer.seconds(60)

    def start_link(opts) do
      name = Keyword.get(opts, :name, __MODULE__)
      GenServer.start_link(__MODULE__, opts, name: name)
    end

    @impl GenServer
    def init(opts) do
      interval = Keyword.get(opts, :polling_interval, @default_polling_interval)
      claim_ttl_ms = Keyword.get(opts, :claim_ttl, @default_claim_ttl_ms)
      repo = Keyword.get(opts, :repo)
      prefix = Keyword.get(opts, :prefix)

      state = %{repo: repo, prefix: prefix, interval: interval, claim_ttl_ms: claim_ttl_ms}

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

    defp fire_overdue_alarms(%{repo: repo, prefix: prefix, claim_ttl_ms: claim_ttl_ms}) do
      now = DateTime.utc_now()
      stale_threshold = DateTime.add(now, -claim_ttl_ms, :millisecond)

      query =
        from(a in DurableObject.Storage.Schemas.Alarm,
          where: a.scheduled_at <= ^now,
          where: is_nil(a.claimed_at) or a.claimed_at <= ^stale_threshold,
          select: {a.object_type, a.object_id, a.alarm_name, a.id}
        )

      repo.all(query, prefix: prefix)
      |> Enum.each(fn {object_type, object_id, alarm_name, alarm_id} ->
        fire_alarm(repo, prefix, object_type, object_id, alarm_name, alarm_id, claim_ttl_ms)
      end)
    end

    defp fire_alarm(repo, prefix, object_type, object_id, alarm_name, alarm_id, claim_ttl_ms) do
      module = String.to_existing_atom(object_type)
      alarm = String.to_existing_atom(alarm_name)

      # Attempt to claim the alarm atomically. If another poller claimed it first,
      # skip this alarm and let the other poller handle it.
      case claim_alarm(repo, prefix, alarm_id, claim_ttl_ms) do
        {:ok, claimed_at} ->
          result =
            try do
              DurableObject.call(module, object_id, :__fire_alarm__, [alarm],
                repo: repo,
                prefix: prefix
              )
            catch
              :exit, reason ->
                {:error, {:exit, reason}}
            end

          case result do
            {:ok, _} ->
              # Success: delete the alarm only if we still own the claim (wasn't rescheduled
              # or reclaimed by another poller after our claim expired).
              delete_if_owned(repo, prefix, alarm_id, claimed_at)

            {:error, {:persistence_failed, reason}} ->
              # Persistence failed: leave the alarm claimed so it retries after TTL expires
              Logger.warning(
                "Alarm #{alarm_name} for #{object_type}:#{object_id} fired but persistence failed: #{inspect(reason)}"
              )

            {:error, reason} ->
              # Handler error: leave the alarm claimed so it retries after TTL expires
              Logger.warning(
                "Failed to fire alarm #{alarm_name} for #{object_type}:#{object_id}: #{inspect(reason)}"
              )
          end

        :not_claimed ->
          # Another poller claimed it first, skip
          :ok
      end
    rescue
      ArgumentError ->
        # Module or alarm atom doesn't exist - delete the orphaned alarm
        Logger.warning(
          "Alarm #{alarm_name} for #{object_type}:#{object_id}: module not loaded, deleting orphaned alarm"
        )

        delete_alarm(repo, prefix, alarm_id)
    end

    defp claim_alarm(repo, prefix, alarm_id, claim_ttl_ms) do
      now = DateTime.utc_now()
      stale_threshold = DateTime.add(now, -claim_ttl_ms, :millisecond)

      {count, _} =
        from(a in DurableObject.Storage.Schemas.Alarm,
          where: a.id == ^alarm_id,
          where: is_nil(a.claimed_at) or a.claimed_at <= ^stale_threshold
        )
        |> repo.update_all([set: [claimed_at: now]], prefix: prefix)

      if count > 0, do: {:ok, now}, else: :not_claimed
    end

    defp delete_if_owned(repo, prefix, alarm_id, claimed_at) do
      # Only delete if we still own the claim. This prevents a slow poller from
      # deleting an alarm that was reclaimed by another poller after TTL expiry.
      from(a in DurableObject.Storage.Schemas.Alarm,
        where: a.id == ^alarm_id,
        where: a.claimed_at == ^claimed_at
      )
      |> repo.delete_all(prefix: prefix)
    rescue
      exception ->
        Logger.error("Failed to delete alarm #{alarm_id}: #{Exception.message(exception)}")
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
