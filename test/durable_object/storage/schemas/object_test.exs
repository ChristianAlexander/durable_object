defmodule DurableObject.Storage.Schemas.ObjectTest do
  use ExUnit.Case, async: true

  alias DurableObject.Storage.Schemas.Object

  describe "changeset/2" do
    test "valid with required fields" do
      changeset = Object.changeset(%Object{}, %{object_type: "Counter", object_id: "test-1"})

      assert changeset.valid?
    end

    test "invalid without object_type" do
      changeset = Object.changeset(%Object{}, %{object_id: "test-1"})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).object_type
    end

    test "invalid without object_id" do
      changeset = Object.changeset(%Object{}, %{object_type: "Counter"})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).object_id
    end

    test "accepts optional fields" do
      changeset =
        Object.changeset(%Object{}, %{
          object_type: "Counter",
          object_id: "test-1",
          state: %{count: 5},
          version: 2,
          locked_by: "node@host",
          locked_at: DateTime.utc_now()
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :state) == %{count: 5}
      assert Ecto.Changeset.get_change(changeset, :version) == 2
    end

    test "defaults state to empty map" do
      object = %Object{}
      assert object.state == %{}
    end

    test "defaults version to 1" do
      object = %Object{}
      assert object.version == 1
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
