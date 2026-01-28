defmodule DurableObject.Storage.Schemas.Alarm do
  @moduledoc """
  Ecto schema for durable_object_alarms table.

  Stores scheduled alarms for Durable Objects, separate from object state.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "durable_object_alarms" do
    field(:object_type, :string)
    field(:object_id, :string)
    field(:alarm_name, :string)
    field(:scheduled_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:object_type, :object_id, :alarm_name, :scheduled_at]

  @doc """
  Creates a changeset for an Alarm.
  """
  def changeset(alarm, attrs) do
    alarm
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end
end
