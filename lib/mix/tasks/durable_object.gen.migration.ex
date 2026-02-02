if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.DurableObject.Gen.Migration do
    @moduledoc """
    Generates an upgrade migration for DurableObject.

    This task scans your existing migrations to find the highest DurableObject
    migration version already applied, then generates a new migration to upgrade
    to the latest version.

    ## Usage

        mix durable_object.gen.migration

    ## Options

    * `--repo` - The Ecto repo to use (defaults to auto-detected repo)

    ## Example

    If your project has a migration with `DurableObject.Migration.up(version: 2)`,
    running this task will generate:

        defmodule MyApp.Repo.Migrations.UpgradeDurableObjectsV3 do
          use Ecto.Migration

          def up, do: DurableObject.Migration.up(base: 2, version: 3)
          def down, do: DurableObject.Migration.down(base: 2, version: 3)
        end
    """

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :durable_object,
        adds_deps: [],
        installs: [],
        example: "mix durable_object.gen.migration",
        positional: [],
        schema: [repo: :string],
        defaults: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      options = igniter.args.options
      current_version = DurableObject.Migration.current_version()

      igniter
      |> then(fn igniter ->
        repo = get_repo(igniter, options)
        igniter = Igniter.include_glob(igniter, "priv/*/migrations/*.exs")

        case find_highest_durable_object_version(igniter) do
          {:ok, 0} ->
            Igniter.add_issue(
              igniter,
              """
              No existing DurableObject migrations found.

              If this is a new installation, run:

                  mix igniter.install durable_object

              If you have an existing migration, ensure it calls DurableObject.Migration.up().
              """
            )

          {:ok, base_version} when base_version >= current_version ->
            Igniter.add_notice(
              igniter,
              """
              Already up to date!

              Your migrations are already at version #{base_version}, which is the latest.
              """
            )

          {:ok, base_version} ->
            generate_upgrade_migration(igniter, repo, base_version, current_version)

          {:unversioned, path} ->
            Igniter.add_issue(
              igniter,
              """
              Found a DurableObject migration without an explicit version:

                  #{path}

              Please update that migration to specify the version that was current when you
              created it. For example, if you created it when DurableObject was at version 2:

                  def up, do: DurableObject.Migration.up(version: 2)
                  def down, do: DurableObject.Migration.down(version: 2)

              Then run this task again.
              """
            )
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

    defp find_highest_durable_object_version(igniter) do
      results =
        igniter.rewrite
        |> Rewrite.sources()
        |> Enum.filter(&match?(%Rewrite.Source{filetype: %Rewrite.Source.Ex{}}, &1))
        |> Enum.filter(&String.contains?(&1.path, "/migrations/"))
        |> Enum.flat_map(&extract_durable_object_versions/1)

      cond do
        Enum.empty?(results) ->
          {:ok, 0}

        Enum.any?(results, &match?({:unversioned, _}, &1)) ->
          {_, path} = Enum.find(results, &match?({:unversioned, _}, &1))
          {:unversioned, path}

        true ->
          {:ok, results |> Enum.map(fn {:ok, v} -> v end) |> Enum.max()}
      end
    end

    defp extract_durable_object_versions(source) do
      source
      |> Rewrite.Source.get(:quoted)
      |> Sourceror.Zipper.zip()
      |> find_migration_versions(source.path, [])
    end

    defp find_migration_versions(zipper, path, versions) do
      case Sourceror.Zipper.next(zipper) do
        nil ->
          versions

        next_zipper ->
          new_versions =
            case extract_version_from_node(next_zipper.node) do
              nil -> versions
              :unversioned -> [{:unversioned, path} | versions]
              version -> [{:ok, version} | versions]
            end

          find_migration_versions(next_zipper, path, new_versions)
      end
    end

    # Match DurableObject.Migration.up(...) or DurableObject.Migration.down(...)
    defp extract_version_from_node(
           {{:., _, [{:__aliases__, _, [:DurableObject, :Migration]}, func]}, _, args}
         )
         when func in [:up, :down] do
      extract_version_from_args(args)
    end

    # Match aliased calls like Migration.up(...) - we can't know for sure it's ours,
    # but if it has version: N, it's likely
    defp extract_version_from_node({{:., _, [{:__aliases__, _, [:Migration]}, func]}, _, args})
         when func in [:up, :down] do
      extract_version_from_args(args)
    end

    defp extract_version_from_node(_), do: nil

    defp extract_version_from_args([]) do
      # up() with no args - we can't know what version was current at the time
      :unversioned
    end

    defp extract_version_from_args([args]) when is_list(args) do
      # Look for version: N in the keyword list
      # Sourceror wraps AST nodes in {:__block__, metadata, [value]} tuples,
      # so we need to handle both standard Elixir AST and Sourceror's format
      Enum.find_value(args, fn
        # Sourceror wrapped format: {:__block__, _, [:version]} for key, {:__block__, _, [N]} for value
        {{:__block__, _, [:version]}, {:__block__, _, [version]}} when is_integer(version) ->
          version

        # Standard Elixir AST format
        {{:version, _, nil}, version} when is_integer(version) ->
          version

        # Simple tuple format
        {:version, version} when is_integer(version) ->
          version

        _ ->
          nil
      end) || :unversioned
    end

    defp extract_version_from_args(_), do: nil

    defp generate_upgrade_migration(igniter, repo, base_version, target_version) do
      body = """
        def up, do: DurableObject.Migration.up(base: #{base_version}, version: #{target_version})
        def down, do: DurableObject.Migration.down(base: #{base_version}, version: #{target_version})
      """

      igniter
      |> Igniter.Libs.Ecto.gen_migration(repo, "upgrade_durable_objects_v#{target_version}",
        body: body
      )
      |> Igniter.add_notice("""
      Generated upgrade migration from version #{base_version} to #{target_version}.

      Run `mix ecto.migrate` to apply the changes.
      """)
    end
  end
end
