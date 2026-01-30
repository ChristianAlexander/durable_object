defmodule DurableObject.TestRepo.Migrations.AddDurableObjects do
  use Ecto.Migration

  def up, do: DurableObject.Migration.up()
  def down, do: DurableObject.Migration.down()
end
