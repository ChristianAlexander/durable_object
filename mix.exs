defmodule DurableObject.MixProject do
  use Mix.Project

  def project do
    [
      app: :durable_object,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
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

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:telemetry, "~> 1.0"},
      {:ecto_sql, "~> 3.10"},
      {:ecto_sqlite3, "~> 0.17", only: [:dev, :test]}
    ]
  end
end
