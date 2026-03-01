defmodule DurableObject.MixProject do
  use Mix.Project

  @version "0.3.2"
  @source_url "https://github.com/ChristianAlexander/durable_object"

  def project do
    [
      app: :durable_object,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      name: "DurableObject",
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  defp description do
    """
    Durable Objects for Elixir - persistent, single-instance objects accessed by ID.
    Provides stateful, persistent actors with automatic lifecycle management.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files:
        ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md usage-rules.md documentation)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: extras(),
      before_closing_body_tag: fn type ->
        if type == :html do
          """
          <script src="https://cdn.jsdelivr.net/npm/mermaid@11.12.2/dist/mermaid.min.js"></script>
          <script>
            mermaid.initialize({
              startOnLoad: true,
              theme: 'default'
            });
          </script>
          """
        end
      end,
      groups_for_extras: groups_for_extras(),
      groups_for_modules: groups_for_modules(),
      nest_modules_by_prefix: [
        DurableObject.Cluster,
        DurableObject.Dsl,
        DurableObject.Scheduler,
        DurableObject.Storage
      ],
      spark: [
        mix_tasks: [
          Formatting: [
            Mix.Tasks.Spark.Formatter
          ]
        ]
      ]
    ]
  end

  defp extras do
    [
      "README.md",
      "guides/lifecycle.md",
      "guides/testing.md",
      "CHANGELOG.md",
      "LICENSE"
    ] ++ Path.wildcard("documentation/**/*.md")
  end

  defp groups_for_extras do
    [
      Guides: ~r/guides\/.*/,
      "DSL Reference": ~r/documentation\/dsls\/.*/
    ]
  end

  defp groups_for_modules do
    [
      "DSL & Core": [
        DurableObject,
        DurableObject.Dsl,
        DurableObject.Dsl.Extension
      ],
      Storage: ~r/DurableObject\.Storage.*/,
      Scheduling: ~r/DurableObject\.Scheduler.*/,
      Internals: ~r/.*/
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
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      docs: [
        "spark.cheat_sheets",
        "docs",
        "spark.replace_doc_links"
      ],
      "spark.cheat_sheets": "spark.cheat_sheets --extensions DurableObject.Dsl.Extension",
      "spark.formatter": "spark.formatter --extensions DurableObject.Dsl.Extension"
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:telemetry, "~> 1.0"},
      {:ecto_sql, "~> 3.10"},
      {:spark, "~> 2.0"},
      {:ecto_sqlite3, "~> 0.17", only: [:dev, :test]},
      {:jason, "~> 1.4"},
      {:horde, "~> 0.10", optional: true},
      {:oban, "~> 2.17", optional: true},
      {:igniter, "~> 0.5", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:sourceror, "~> 1.7"}
    ]
  end
end
