import Config

if config_env() == :test do
  config :durable_object, DurableObject.TestRepo,
    database: "tmp/test.db",
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 10

  config :durable_object,
    ecto_repos: [DurableObject.TestRepo],
    # NOTE: No default repo - tests that need persistence pass repo: TestRepo explicitly
    scheduler: DurableObject.Scheduler.Polling,
    scheduler_opts: [polling_interval: :timer.seconds(60)]

  config :logger, level: :warning
end
