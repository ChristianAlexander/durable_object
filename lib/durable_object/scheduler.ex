defmodule DurableObject.Scheduler do
  @moduledoc """
  Behaviour for alarm scheduling backends.

  Implementations must handle:
  - Scheduling alarms for future execution
  - Cancelling pending alarms
  - Resurrecting alarms after process/node crashes

  ## Built-in Implementations

    * `DurableObject.Scheduler.Polling` - Database-backed polling scheduler (default)
    * `DurableObject.Scheduler.Oban` - Oban-based scheduler (requires oban dependency)

  ## Configuration

  ### Polling Scheduler (default)

      config :durable_object,
        scheduler: DurableObject.Scheduler.Polling,
        scheduler_opts: [
          repo: MyApp.Repo,
          polling_interval: :timer.seconds(30)
        ]

  ### Oban Scheduler

  For applications already using Oban, the Oban scheduler leverages your existing
  Oban infrastructure for alarm delivery.

      config :durable_object,
        scheduler: DurableObject.Scheduler.Oban,
        scheduler_opts: [
          oban_instance: MyApp.Oban,  # Optional, defaults to Oban
          oban_queue: :durable_object_alarms  # Optional, default shown
        ]

  You must also add the queue to your Oban configuration:

      config :my_app, Oban,
        repo: MyApp.Repo,
        queues: [durable_object_alarms: 5]

  """

  @type object_ref :: {module :: module(), object_id :: String.t()}
  @type alarm_name :: atom()
  @type delay_ms :: non_neg_integer()

  @doc """
  Schedule an alarm to fire after `delay_ms` milliseconds.
  If an alarm with the same name already exists, it should be replaced.
  """
  @callback schedule(object_ref(), alarm_name(), delay_ms(), opts :: keyword()) ::
              :ok | {:error, term()}

  @doc """
  Cancel a pending alarm.
  Returns :ok even if the alarm doesn't exist.
  """
  @callback cancel(object_ref(), alarm_name(), opts :: keyword()) ::
              :ok | {:error, term()}

  @doc """
  Cancel all alarms for an object.
  """
  @callback cancel_all(object_ref(), opts :: keyword()) ::
              :ok | {:error, term()}

  @doc """
  List all pending alarms for an object.
  Returns a list of {alarm_name, scheduled_at} tuples.
  """
  @callback list(object_ref(), opts :: keyword()) ::
              {:ok, [{alarm_name(), DateTime.t()}]} | {:error, term()}

  @doc """
  Child spec for the scheduler's supervision tree (poller, etc).
  Return an empty list if no children are needed.
  """
  @callback child_spec(opts :: keyword()) :: [Supervisor.child_spec()]
end
