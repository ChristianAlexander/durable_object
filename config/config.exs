import Config

if config_env() == :test do
  config :durable_object, DurableObject.TestRepo,
    database: "tmp/test.db",
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 10

  config :durable_object, ecto_repos: [DurableObject.TestRepo]

  config :logger, level: :warning
end
