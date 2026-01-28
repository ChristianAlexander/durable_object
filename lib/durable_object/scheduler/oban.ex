if Code.ensure_loaded?(Oban) do
  defmodule DurableObject.Scheduler.Oban do
    @moduledoc """
    Oban-based alarm scheduler.

    This scheduler uses Oban's job processing infrastructure to deliver alarms.
    It's ideal for applications that already use Oban, as it leverages the existing
    setup and provides Oban's robust features (retries, observability, etc.).

    ## Configuration

        config :durable_object,
          scheduler: DurableObject.Scheduler.Oban,
          scheduler_opts: [
            oban_instance: MyApp.Oban,  # Required: your Oban instance name
            oban_queue: :durable_object_alarms  # Optional, default shown
          ]

    You must also add the queue to your Oban configuration:

        config :my_app, Oban,
          repo: MyApp.Repo,
          queues: [
            default: 10,
            durable_object_alarms: 5
          ]

    ## How It Works

    - Alarms are scheduled as Oban jobs with `schedule_in`
    - When the job executes, it fires the alarm via `DurableObject.call/5`
    - Jobs use Oban's uniqueness to prevent duplicate alarms
    - Failed alarms are retried according to Oban's retry policy (max 3 attempts)

    ## Supervision

    Unlike the polling scheduler, the Oban scheduler does not add any children
    to the supervision tree. Oban manages its own supervision and the worker
    jobs run within Oban's infrastructure.
    """

    @behaviour DurableObject.Scheduler

    import Ecto.Query

    @default_queue :durable_object_alarms

    @impl DurableObject.Scheduler
    def schedule({module, object_id}, alarm_name, delay_ms, opts) do
      oban_name = Keyword.fetch!(opts, :oban_instance)
      queue = Keyword.get(opts, :oban_queue, @default_queue)

      job_args = %{
        "object_type" => to_string(module),
        "object_id" => object_id,
        "alarm_name" => to_string(alarm_name)
      }

      # Cancel existing alarm first to ensure rescheduling works correctly
      cancel({module, object_id}, alarm_name, opts)

      # Schedule new alarm
      # Note: schedule_in is in seconds, so we convert from milliseconds
      schedule_in_seconds = max(div(delay_ms, 1000), 0)

      job_args
      |> DurableObject.Scheduler.Oban.Worker.new(
        schedule_in: schedule_in_seconds,
        queue: queue
      )
      |> Oban.insert(oban_name)
      |> case do
        {:ok, _job} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end

    @impl DurableObject.Scheduler
    def cancel({module, object_id}, alarm_name, opts) do
      oban_name = Keyword.fetch!(opts, :oban_instance)
      worker = to_string(DurableObject.Scheduler.Oban.Worker)

      {:ok, _count} =
        Oban.cancel_all_jobs(oban_name, fn query ->
          query
          |> where([j], j.worker == ^worker)
          |> where([j], j.state in ["available", "scheduled", "retryable"])
          |> where([j], fragment("?->>'object_type' = ?", j.args, ^to_string(module)))
          |> where([j], fragment("?->>'object_id' = ?", j.args, ^object_id))
          |> where([j], fragment("?->>'alarm_name' = ?", j.args, ^to_string(alarm_name)))
        end)

      :ok
    end

    @impl DurableObject.Scheduler
    def cancel_all({module, object_id}, opts) do
      oban_name = Keyword.fetch!(opts, :oban_instance)
      worker = to_string(DurableObject.Scheduler.Oban.Worker)

      {:ok, _count} =
        Oban.cancel_all_jobs(oban_name, fn query ->
          query
          |> where([j], j.worker == ^worker)
          |> where([j], j.state in ["available", "scheduled", "retryable"])
          |> where([j], fragment("?->>'object_type' = ?", j.args, ^to_string(module)))
          |> where([j], fragment("?->>'object_id' = ?", j.args, ^object_id))
        end)

      :ok
    end

    @impl DurableObject.Scheduler
    def list({module, object_id}, opts) do
      oban_name = Keyword.fetch!(opts, :oban_instance)
      conf = Oban.config(oban_name)
      worker = to_string(DurableObject.Scheduler.Oban.Worker)

      jobs =
        Oban.Job
        |> where([j], j.worker == ^worker)
        |> where([j], j.state in ["available", "scheduled", "retryable"])
        |> where([j], fragment("?->>'object_type' = ?", j.args, ^to_string(module)))
        |> where([j], fragment("?->>'object_id' = ?", j.args, ^object_id))
        |> order_by([j], asc: j.scheduled_at)
        |> conf.repo.all()
        |> Enum.map(fn job ->
          alarm_name = String.to_existing_atom(job.args["alarm_name"])
          {alarm_name, job.scheduled_at}
        end)

      {:ok, jobs}
    end

    @impl DurableObject.Scheduler
    def child_spec(_opts) do
      # Oban manages its own supervision - no children needed
      []
    end

    # --- Worker ---

    defmodule Worker do
      @moduledoc false
      use Oban.Worker, queue: :durable_object_alarms, max_attempts: 3

      require Logger

      @impl Oban.Worker
      def perform(%Oban.Job{args: args}) do
        %{
          "object_type" => object_type,
          "object_id" => object_id,
          "alarm_name" => alarm_name
        } = args

        module = String.to_existing_atom(object_type)
        alarm = String.to_existing_atom(alarm_name)

        case DurableObject.call(module, object_id, :__fire_alarm__, [alarm]) do
          {:ok, _} ->
            :ok

          {:error, {:persistence_failed, reason}} ->
            # Persistence failed - let Oban retry
            Logger.warning(
              "Alarm #{alarm_name} for #{object_type}:#{object_id} fired but persistence failed, " <>
                "will retry: #{inspect(reason)}"
            )

            {:error, reason}

          {:error, reason} ->
            Logger.warning(
              "Failed to fire alarm #{alarm_name} for #{object_type}:#{object_id}: #{inspect(reason)}"
            )

            {:error, reason}
        end
      rescue
        ArgumentError ->
          # Module or alarm atom doesn't exist - don't retry
          Logger.warning(
            "Discarding alarm #{args["alarm_name"]} for #{args["object_type"]}:#{args["object_id"]}: " <>
              "module or alarm not loaded"
          )

          :ok
      end
    end
  end
end
