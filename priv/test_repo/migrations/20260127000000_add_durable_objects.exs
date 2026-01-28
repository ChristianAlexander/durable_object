defmodule DurableObject.TestRepo.Migrations.AddDurableObjects do
  use Ecto.Migration

  def up do
    DurableObject.Migration.up(version: 1)
  end

  def down do
    DurableObject.Migration.down(version: 1)
  end
end
