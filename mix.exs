defmodule DurableObject.MixProject do
  use Mix.Project

  def project do
    [
      app: :durable_object,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {DurableObject.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:telemetry, "~> 1.0"},
      {:ecto_sql, "~> 3.10"},
      {:spark, "~> 2.0"},
      {:ecto_sqlite3, "~> 0.17", only: [:dev, :test]},
      {:jason, "~> 1.4", only: [:dev, :test]},
      {:horde, "~> 0.9", optional: true}
    ]
  end
end
