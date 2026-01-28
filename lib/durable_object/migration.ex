defmodule DurableObject.Migration do
  @moduledoc """
  Versioned migrations for DurableObject tables.

  ## Usage

  Generate a migration:

      mix ecto.gen.migration add_durable_objects

  Then call the versioned migration functions:

      defmodule MyApp.Repo.Migrations.AddDurableObjects do
        use Ecto.Migration

        def up, do: DurableObject.Migration.up(version: 1)
        def down, do: DurableObject.Migration.down(version: 1)
      end

  ## Upgrading

  When upgrading to a new version of DurableObject that requires schema changes,
  generate a new migration and specify the new version:

      defmodule MyApp.Repo.Migrations.UpgradeDurableObjectsV2 do
        use Ecto.Migration

        def up, do: DurableObject.Migration.up(version: 2)
        def down, do: DurableObject.Migration.down(version: 2)
      end
  """

  use Ecto.Migration

  @current_version 2

  @doc """
  Returns the current migration version.
  """
  def current_version, do: @current_version

  @doc """
  Runs migrations up to the specified version.

  ## Options

    * `:version` - Target version (default: current version)
    * `:prefix` - Table prefix for multi-tenancy (default: nil)
  """
  def up(opts \\ []) do
    version = Keyword.get(opts, :version, @current_version)
    prefix = Keyword.get(opts, :prefix)

    for v <- 1..version do
      apply_change(v, :up, prefix)
    end
  end

  @doc """
  Runs migrations down to the specified version.

  ## Options

    * `:version` - Target version to roll back to (default: 1)
    * `:prefix` - Table prefix for multi-tenancy (default: nil)
  """
  def down(opts \\ []) do
    version = Keyword.get(opts, :version, 1)
    prefix = Keyword.get(opts, :prefix)

    for v <- @current_version..version//-1 do
      apply_change(v, :down, prefix)
    end
  end

  # Version 1: Initial tables
  defp apply_change(1, :up, prefix) do
    # Objects table - stores state as JSON blob
    create table(:durable_objects, prefix: prefix) do
      add(:object_type, :string, null: false)
      add(:object_id, :string, null: false)
      add(:state, :map, null: false, default: %{})
      add(:version, :integer, default: 1)
      add(:locked_by, :string)
      add(:locked_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:durable_objects, [:object_type, :object_id], prefix: prefix))
    create(index(:durable_objects, [:locked_by], prefix: prefix))

    # Alarms table - separate from object state
    create table(:durable_object_alarms, prefix: prefix) do
      add(:object_type, :string, null: false)
      add(:object_id, :string, null: false)
      add(:alarm_name, :string, null: false)
      add(:scheduled_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:durable_object_alarms, [:object_type, :object_id, :alarm_name],
        prefix: prefix
      )
    )

    create(index(:durable_object_alarms, [:scheduled_at], prefix: prefix))
  end

  defp apply_change(1, :down, prefix) do
    drop_if_exists(table(:durable_object_alarms, prefix: prefix))
    drop_if_exists(table(:durable_objects, prefix: prefix))
  end

  # Version 2: Remove unused locking columns
  defp apply_change(2, :up, prefix) do
    drop_if_exists(index(:durable_objects, [:locked_by], prefix: prefix))

    alter table(:durable_objects, prefix: prefix) do
      remove_if_exists(:locked_by, :string)
      remove_if_exists(:locked_at, :utc_datetime_usec)
    end
  end

  defp apply_change(2, :down, prefix) do
    alter table(:durable_objects, prefix: prefix) do
      add_if_not_exists(:locked_by, :string)
      add_if_not_exists(:locked_at, :utc_datetime_usec)
    end

    create_if_not_exists(index(:durable_objects, [:locked_by], prefix: prefix))
  end
end
