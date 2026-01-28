defmodule DurableObject.Storage do
  @moduledoc """
  Handles persistence of Durable Object state to the database.

  State is stored as a JSON blob, accessed by (object_type, object_id) pair.
  """

  import Ecto.Query

  alias DurableObject.Storage.Schemas.Object

  @doc """
  Loads a Durable Object from the database.

  Returns `{:ok, object}` if found, `{:ok, nil}` if not found.

  ## Options

    * `:prefix` - Table prefix for multi-tenancy (default: nil)
  """
  def load(repo, object_type, object_id, opts \\ []) do
    prefix = Keyword.get(opts, :prefix)

    query =
      from(o in Object,
        where: o.object_type == ^object_type and o.object_id == ^object_id
      )

    case repo.one(query, prefix: prefix) do
      nil -> {:ok, nil}
      object -> {:ok, object}
    end
  end

  @doc """
  Saves a Durable Object to the database.

  Uses upsert to insert or update based on (object_type, object_id).
  Sets locked_by to the current node.

  ## Options

    * `:prefix` - Table prefix for multi-tenancy (default: nil)
  """
  def save(repo, object_type, object_id, state, opts \\ []) do
    prefix = Keyword.get(opts, :prefix)
    node = Node.self() |> to_string()
    now = DateTime.utc_now()

    attrs = %{
      object_type: object_type,
      object_id: object_id,
      state: state,
      locked_by: node,
      locked_at: now
    }

    repo.insert(
      Object.changeset(%Object{}, attrs),
      on_conflict: [set: [state: state, locked_by: node, locked_at: now, updated_at: now]],
      conflict_target: [:object_type, :object_id],
      prefix: prefix
    )
  end

  @doc """
  Releases the lock on a Durable Object.

  Called when a process terminates to allow other nodes to claim it.

  ## Options

    * `:prefix` - Table prefix for multi-tenancy (default: nil)
  """
  def release_lock(repo, object_type, object_id, opts \\ []) do
    prefix = Keyword.get(opts, :prefix)

    from(o in Object,
      where: o.object_type == ^object_type and o.object_id == ^object_id
    )
    |> repo.update_all([set: [locked_by: nil, locked_at: nil]], prefix: prefix)

    :ok
  end

  @doc """
  Deletes a Durable Object from the database.

  ## Options

    * `:prefix` - Table prefix for multi-tenancy (default: nil)
  """
  def delete(repo, object_type, object_id, opts \\ []) do
    prefix = Keyword.get(opts, :prefix)

    from(o in Object,
      where: o.object_type == ^object_type and o.object_id == ^object_id
    )
    |> repo.delete_all(prefix: prefix)

    :ok
  end
end
