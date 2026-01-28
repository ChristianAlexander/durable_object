if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.DurableObject.Install do
    @moduledoc """
    Installs DurableObject into your project.

    ## Options

    * `--repo` - The Ecto repo to use (defaults to auto-detected repo)
    * `--scheduler` - Alarm scheduler: `polling` (default) or `oban`
    * `--oban-instance` - Required if using Oban scheduler
    * `--oban-queue` - Oban queue name (default: `durable_object_alarms`)
    * `--distributed` - Enable Horde for distributed mode

    ## Example

        mix igniter.install durable_object
        mix igniter.install durable_object --scheduler oban --oban-instance MyApp.Oban
        mix igniter.install durable_object --distributed
    """

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :durable_object,
        adds_deps: [],
        installs: [],
        example: "mix igniter.install durable_object --repo MyApp.Repo",
        positional: [],
        schema: [
          repo: :string,
          scheduler: :string,
          oban_instance: :string,
          oban_queue: :string,
          distributed: :boolean
        ],
        defaults: [
          scheduler: "polling",
          oban_queue: "durable_object_alarms",
          distributed: false
        ]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      options = igniter.args.options
      scheduler = String.to_atom(options[:scheduler] || "polling")

      igniter
      |> validate_options(options, scheduler)
      |> then(fn igniter ->
        if igniter.issues != [] do
          igniter
        else
          repo = get_repo(igniter, options)

          igniter
          |> Igniter.Project.Formatter.import_dep(:durable_object)
          |> add_configuration(repo, scheduler, options)
          |> generate_migration(repo)
          |> maybe_add_oban_notice(scheduler, options)
          |> add_next_steps_notice()
        end
      end)
    end

    defp get_repo(igniter, options) do
      case options[:repo] do
        nil ->
          case Igniter.Libs.Ecto.list_repos(igniter) do
            {_igniter, [repo | _]} -> repo
            _ -> raise "Could not auto-detect repo. Please specify --repo"
          end

        repo_string ->
          Module.concat([repo_string])
      end
    end

    defp validate_options(igniter, options, :oban) do
      if is_nil(options[:oban_instance]) do
        Igniter.add_issue(igniter, """
        The Oban scheduler requires --oban-instance to be specified.

        Example: mix igniter.install durable_object --scheduler oban --oban-instance MyApp.Oban
        """)
      else
        igniter
      end
    end

    defp validate_options(igniter, _options, _scheduler), do: igniter

    defp add_configuration(igniter, repo, scheduler, options) do
      distributed = options[:distributed] || false

      base_config = [
        repo: repo,
        registry_mode: if(distributed, do: :horde, else: :local)
      ]

      scheduler_config =
        case scheduler do
          :polling ->
            [
              scheduler: DurableObject.Scheduler.Polling,
              scheduler_opts:
                {:code, Sourceror.parse_string!("[polling_interval: :timer.seconds(30)]")}
            ]

          :oban ->
            oban_instance = Module.concat([options[:oban_instance]])
            queue = String.to_atom(options[:oban_queue] || "durable_object_alarms")

            [
              scheduler: DurableObject.Scheduler.Oban,
              scheduler_opts: [
                oban_instance: oban_instance,
                oban_queue: queue
              ]
            ]
        end

      config = Keyword.merge(base_config, scheduler_config)

      Enum.reduce(config, igniter, fn {key, value}, acc ->
        Igniter.Project.Config.configure(
          acc,
          "config.exs",
          :durable_object,
          [key],
          value
        )
      end)
    end

    defp generate_migration(igniter, repo) do
      repo_name = Module.split(repo) |> List.last()

      migration_content = """
      defmodule #{inspect(repo)}.Migrations.AddDurableObjects do
        use Ecto.Migration

        def up do
          DurableObject.Migration.up(version: 1)
        end

        # We specify version: 1 in down, ensuring that we'll roll all the way back
        # down if necessary, regardless of which version we've migrated up to.
        def down do
          DurableObject.Migration.down(version: 1)
        end
      end
      """

      timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d%H%M%S")
      path = "priv/#{String.downcase(repo_name)}/migrations/#{timestamp}_add_durable_objects.exs"

      Igniter.create_new_file(igniter, path, migration_content)
    end

    defp maybe_add_oban_notice(igniter, :oban, options) do
      queue = options[:oban_queue] || "durable_object_alarms"

      Igniter.add_notice(igniter, """
      Oban Queue Setup Required

      Add the following queue to your Oban configuration:

          config :your_app, Oban,
            queues: [
              #{queue}: 5
            ]
      """)
    end

    defp maybe_add_oban_notice(igniter, _scheduler, _options), do: igniter

    defp add_next_steps_notice(igniter) do
      Igniter.add_notice(igniter, """
      DurableObject installed successfully.

      Next steps:

      1. Run `mix ecto.migrate` to create the database tables

      2. Create your first Durable Object:

          defmodule MyApp.Counter do
            use DurableObject

            state do
              field :count, :integer, default: 0
            end

            handlers do
              handler :increment
              handler :get
            end

            def handle_increment(state) do
              new_count = Map.get(state, :count, 0) + 1
              {:reply, new_count, Map.put(state, :count, new_count)}
            end

            def handle_get(state) do
              {:reply, state, state}
            end
          end

      3. Use it in your application:

          {:ok, count} = MyApp.Counter.increment("user-123")

      Documentation: https://hexdocs.pm/durable_object
      """)
    end
  end
end
