defmodule DurableObject.Storage do
  @moduledoc """
  Handles persistence of Durable Object state to the database.

  State is stored as a JSON blob, accessed by (object_type, object_id) pair.

  All operations emit telemetry events and log errors on failure.
  See `DurableObject.Telemetry` for event details.
  """

  import Ecto.Query
  require Logger

  alias DurableObject.Storage.Schemas.Object
  alias DurableObject.Telemetry

  @doc """
  Loads a Durable Object from the database.

  Returns `{:ok, object}` if found, `{:ok, nil}` if not found,
  or `{:error, {:load_failed, exception}}` on database error.

  ## Options

    * `:prefix` - Table prefix for multi-tenancy (default: nil)
  """
  def load(repo, object_type, object_id, opts \\ []) do
    prefix = Keyword.get(opts, :prefix)

    metadata = %{
      repo: repo,
      object_type: object_type,
      object_id: object_id
    }

    case Telemetry.span([:durable_object, :storage, :load], metadata, fn ->
           query =
             from(o in Object,
               where: o.object_type == ^object_type and o.object_id == ^object_id
             )

           case repo.one(query, prefix: prefix) do
             nil -> {:ok, nil}
             object -> {:ok, object}
           end
         end) do
      {:ok, result} ->
        result

      {:error, exception} ->
        Logger.error(
          "Failed to load durable object #{object_type}:#{object_id}: #{Exception.message(exception)}"
        )

        {:error, {:load_failed, exception}}
    end
  end

  @doc """
  Saves a Durable Object to the database.

  Uses upsert to insert or update based on (object_type, object_id).

  Returns `{:ok, object}` on success, `{:error, changeset}` on validation error,
  or `{:error, {:save_failed, exception}}` on database error.

  ## Options

    * `:prefix` - Table prefix for multi-tenancy (default: nil)
  """
  def save(repo, object_type, object_id, state, opts \\ []) do
    prefix = Keyword.get(opts, :prefix)
    now = DateTime.utc_now()

    attrs = %{
      object_type: object_type,
      object_id: object_id,
      state: state
    }

    metadata = %{
      repo: repo,
      object_type: object_type,
      object_id: object_id
    }

    case Telemetry.span([:durable_object, :storage, :save], metadata, fn ->
           repo.insert(
             Object.changeset(%Object{}, attrs),
             on_conflict: [set: [state: state, updated_at: now]],
             conflict_target: [:object_type, :object_id],
             prefix: prefix
           )
         end) do
      {:ok, result} ->
        result

      {:error, exception} ->
        Logger.error(
          "Failed to save durable object #{object_type}:#{object_id}: #{Exception.message(exception)}"
        )

        {:error, {:save_failed, exception}}
    end
  end

  @doc """
  Deletes a Durable Object from the database.

  Returns `:ok` on success or `{:error, {:delete_failed, exception}}` on failure.

  ## Options

    * `:prefix` - Table prefix for multi-tenancy (default: nil)
  """
  def delete(repo, object_type, object_id, opts \\ []) do
    prefix = Keyword.get(opts, :prefix)

    metadata = %{
      repo: repo,
      object_type: object_type,
      object_id: object_id
    }

    case Telemetry.span([:durable_object, :storage, :delete], metadata, fn ->
           from(o in Object,
             where: o.object_type == ^object_type and o.object_id == ^object_id
           )
           |> repo.delete_all(prefix: prefix)

           :ok
         end) do
      {:ok, :ok} ->
        :ok

      {:error, exception} ->
        Logger.error(
          "Failed to delete durable object #{object_type}:#{object_id}: #{Exception.message(exception)}"
        )

        {:error, {:delete_failed, exception}}
    end
  end
end
