defmodule DurableObject.Storage.Schemas.Object do
  @moduledoc """
  Ecto schema for durable_objects table.

  Stores the state of Durable Objects as JSON blobs, indexed by
  (object_type, object_id) pair.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "durable_objects" do
    field(:object_type, :string)
    field(:object_id, :string)
    field(:state, :map, default: %{})
    field(:version, :integer, default: 1)

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:object_type, :object_id]
  @optional_fields [:state, :version]

  @doc """
  Creates a changeset for an Object.
  """
  def changeset(object, attrs) do
    object
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
