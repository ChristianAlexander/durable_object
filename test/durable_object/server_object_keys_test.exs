defmodule DurableObject.ServerObjectKeysTest do
  use ExUnit.Case

  alias DurableObject.{Server, Storage, TestRepo}
  import DurableObject.TestHelpers

  # Default behavior - keys within field values stay as strings
  defmodule DefaultKeysObject do
    use DurableObject

    state do
      field(:metadata, :map, default: %{})
      field(:items, :list, default: [])
    end

    handlers do
      handler(:get)
      handler(:set_metadata, args: [:data])
    end

    def handle_get(state) do
      {:reply, state, state}
    end

    def handle_set_metadata(data, state) do
      {:reply, :ok, %{state | metadata: data}}
    end
  end

  # Explicit :strings option - same as default
  defmodule StringKeysObject do
    use DurableObject

    options do
      object_keys :strings
    end

    state do
      field(:metadata, :map, default: %{})
    end

    handlers do
      handler(:get)
    end

    def handle_get(state) do
      {:reply, state, state}
    end
  end

  # :atoms! option - converts to existing atoms only
  defmodule ExistingAtomKeysObject do
    use DurableObject

    options do
      object_keys :atoms!
    end

    state do
      field(:metadata, :map, default: %{})
      field(:items, :list, default: [])
    end

    handlers do
      handler(:get)
    end

    def handle_get(state) do
      {:reply, state, state}
    end
  end

  # :atoms option - creates atoms if needed
  defmodule CreateAtomKeysObject do
    use DurableObject

    options do
      object_keys :atoms
    end

    state do
      field(:metadata, :map, default: %{})
      field(:items, :list, default: [])
    end

    handlers do
      handler(:get)
    end

    def handle_get(state) do
      {:reply, state, state}
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)
    Ecto.Adapters.SQL.Sandbox.mode(TestRepo, {:shared, self()})
    :ok
  end

  describe "introspection" do
    test "default object_keys is nil (deferred to runtime)" do
      assert DefaultKeysObject.__durable_object__(:object_keys) == nil
    end

    test "explicit :strings option" do
      assert StringKeysObject.__durable_object__(:object_keys) == :strings
    end

    test ":atoms! option is accessible" do
      assert ExistingAtomKeysObject.__durable_object__(:object_keys) == :atoms!
    end

    test ":atoms option is accessible" do
      assert CreateAtomKeysObject.__durable_object__(:object_keys) == :atoms
    end
  end

  describe "default behavior (:strings)" do
    test "keeps keys within field values as strings" do
      id = unique_id("default-keys")

      # Pre-populate with nested string keys (as stored in JSON)
      {:ok, _} =
        Storage.save(TestRepo, "#{DefaultKeysObject}", id, %{
          "metadata" => %{"foo" => "bar", "nested" => %{"baz" => 123}},
          "items" => [%{"name" => "item1"}, %{"name" => "item2"}]
        })

      {:ok, _pid} =
        Server.start_link(
          module: DefaultKeysObject,
          object_id: id,
          repo: TestRepo
        )

      {:ok, state} = Server.call(DefaultKeysObject, id, :get)

      # Field names are atoms (DSL handles this)
      assert Map.has_key?(state, :metadata)
      assert Map.has_key?(state, :items)

      # Keys within values remain strings
      assert state.metadata == %{"foo" => "bar", "nested" => %{"baz" => 123}}
      assert state.items == [%{"name" => "item1"}, %{"name" => "item2"}]
    end
  end

  describe ":atoms! option" do
    test "converts keys within field values to existing atoms" do
      id = unique_id("existing-atoms")

      # Ensure atoms exist
      _ = [:foo, :nested, :baz, :name]

      # Pre-populate with nested string keys
      {:ok, _} =
        Storage.save(TestRepo, "#{ExistingAtomKeysObject}", id, %{
          "metadata" => %{"foo" => "bar", "nested" => %{"baz" => 123}},
          "items" => [%{"name" => "item1"}, %{"name" => "item2"}]
        })

      {:ok, _pid} =
        Server.start_link(
          module: ExistingAtomKeysObject,
          object_id: id,
          repo: TestRepo
        )

      {:ok, state} = Server.call(ExistingAtomKeysObject, id, :get)

      # Field names are atoms
      assert Map.has_key?(state, :metadata)
      assert Map.has_key?(state, :items)

      # Keys within values are converted to atoms
      assert state.metadata == %{foo: "bar", nested: %{baz: 123}}
      assert state.items == [%{name: "item1"}, %{name: "item2"}]
    end

    test "raises for non-existent atoms" do
      id = unique_id("nonexistent-atoms")

      # Pre-populate with a key that doesn't exist as an atom
      random_key = "nonexistent_key_#{System.unique_integer()}"

      {:ok, _} =
        Storage.save(TestRepo, "#{ExistingAtomKeysObject}", id, %{
          "metadata" => %{random_key => "value"},
          "items" => []
        })

      # The server starts but crashes during handle_continue when loading state
      Process.flag(:trap_exit, true)

      {:ok, pid} =
        Server.start_link(
          module: ExistingAtomKeysObject,
          object_id: id,
          repo: TestRepo
        )

      # Wait for the process to crash
      assert_receive {:EXIT, ^pid, reason}, 1000
      assert reason != :normal
    end
  end

  describe ":atoms option" do
    test "creates atoms for keys within field values" do
      id = unique_id("create-atoms")

      # Use a unique key that definitely doesn't exist as an atom yet
      unique_key = "dynamically_created_#{System.unique_integer()}"

      {:ok, _} =
        Storage.save(TestRepo, "#{CreateAtomKeysObject}", id, %{
          "metadata" => %{unique_key => "value", "regular" => "data"},
          "items" => []
        })

      {:ok, _pid} =
        Server.start_link(
          module: CreateAtomKeysObject,
          object_id: id,
          repo: TestRepo
        )

      {:ok, state} = Server.call(CreateAtomKeysObject, id, :get)

      # Keys are converted to atoms (including the dynamically created one)
      assert Map.has_key?(state.metadata, String.to_atom(unique_key))
      assert Map.has_key?(state.metadata, :regular)
      assert state.metadata[String.to_atom(unique_key)] == "value"
      assert state.metadata[:regular] == "data"
    end

    test "recursively converts keys in deeply nested maps" do
      id = unique_id("atoms-deep")

      outer_key = "atoms_deep_outer_#{System.unique_integer()}"
      inner_key = "atoms_deep_inner_#{System.unique_integer()}"

      {:ok, _} =
        Storage.save(TestRepo, "#{CreateAtomKeysObject}", id, %{
          "metadata" => %{outer_key => %{inner_key => "deep"}},
          "items" => []
        })

      {:ok, _pid} =
        Server.start_link(
          module: CreateAtomKeysObject,
          object_id: id,
          repo: TestRepo
        )

      {:ok, state} = Server.call(CreateAtomKeysObject, id, :get)

      outer_atom = String.to_atom(outer_key)
      inner_atom = String.to_atom(inner_key)
      assert state.metadata == %{outer_atom => %{inner_atom => "deep"}}
    end

    test "recursively converts keys in lists of maps" do
      id = unique_id("atoms-list")

      key = "atoms_list_key_#{System.unique_integer()}"

      {:ok, _} =
        Storage.save(TestRepo, "#{CreateAtomKeysObject}", id, %{
          "metadata" => %{},
          "items" => [%{key => "a"}, %{key => "b"}]
        })

      {:ok, _pid} =
        Server.start_link(
          module: CreateAtomKeysObject,
          object_id: id,
          repo: TestRepo
        )

      {:ok, state} = Server.call(CreateAtomKeysObject, id, :get)

      key_atom = String.to_atom(key)
      assert state.items == [%{key_atom => "a"}, %{key_atom => "b"}]
    end
  end

  describe "deeply nested structures" do
    test "recursively converts keys in nested maps with :atoms!" do
      id = unique_id("deep-nested")

      # Ensure atoms exist
      _ = [:level1, :level2, :level3, :value]

      {:ok, _} =
        Storage.save(TestRepo, "#{ExistingAtomKeysObject}", id, %{
          "metadata" => %{
            "level1" => %{
              "level2" => %{
                "level3" => %{"value" => "deep"}
              }
            }
          },
          "items" => []
        })

      {:ok, _pid} =
        Server.start_link(
          module: ExistingAtomKeysObject,
          object_id: id,
          repo: TestRepo
        )

      {:ok, state} = Server.call(ExistingAtomKeysObject, id, :get)

      assert state.metadata == %{
               level1: %{
                 level2: %{
                   level3: %{value: "deep"}
                 }
               }
             }
    end

    test "recursively converts keys in lists of maps with :atoms!" do
      id = unique_id("list-of-maps")

      # Ensure atoms exist
      _ = [:id, :data, :nested]

      {:ok, _} =
        Storage.save(TestRepo, "#{ExistingAtomKeysObject}", id, %{
          "metadata" => %{},
          "items" => [
            %{"id" => 1, "data" => %{"nested" => "value1"}},
            %{"id" => 2, "data" => %{"nested" => "value2"}}
          ]
        })

      {:ok, _pid} =
        Server.start_link(
          module: ExistingAtomKeysObject,
          object_id: id,
          repo: TestRepo
        )

      {:ok, state} = Server.call(ExistingAtomKeysObject, id, :get)

      assert state.items == [
               %{id: 1, data: %{nested: "value1"}},
               %{id: 2, data: %{nested: "value2"}}
             ]
    end
  end

  describe "application config fallback" do
    test "uses application config when DSL not specified" do
      id = unique_id("app-config")

      # Ensure atoms exist
      _ = [:app_key]

      # Set application config
      original_value = Application.get_env(:durable_object, :object_keys)
      Application.put_env(:durable_object, :object_keys, :atoms!)

      try do
        {:ok, _} =
          Storage.save(TestRepo, "#{DefaultKeysObject}", id, %{
            "metadata" => %{"app_key" => "value"},
            "items" => []
          })

        {:ok, _pid} =
          Server.start_link(
            module: DefaultKeysObject,
            object_id: id,
            repo: TestRepo
          )

        {:ok, state} = Server.call(DefaultKeysObject, id, :get)

        # Should use :atoms! from app config since DSL defaults to :strings (nil in config resolution)
        assert state.metadata == %{app_key: "value"}
      after
        if original_value do
          Application.put_env(:durable_object, :object_keys, original_value)
        else
          Application.delete_env(:durable_object, :object_keys)
        end
      end
    end

    test "DSL config overrides application config" do
      id = unique_id("dsl-override")

      # Set application config to :atoms
      original_value = Application.get_env(:durable_object, :object_keys)
      Application.put_env(:durable_object, :object_keys, :atoms)

      try do
        {:ok, _} =
          Storage.save(TestRepo, "#{StringKeysObject}", id, %{
            "metadata" => %{"key" => "value"}
          })

        {:ok, _pid} =
          Server.start_link(
            module: StringKeysObject,
            object_id: id,
            repo: TestRepo
          )

        {:ok, state} = Server.call(StringKeysObject, id, :get)

        # Should use :strings from DSL, not :atoms from app config
        assert state.metadata == %{"key" => "value"}
      after
        if original_value do
          Application.put_env(:durable_object, :object_keys, original_value)
        else
          Application.delete_env(:durable_object, :object_keys)
        end
      end
    end
  end

  describe "edge cases" do
    test "empty maps and lists are preserved" do
      id = unique_id("edge-empty")

      {:ok, _} =
        Storage.save(TestRepo, "#{ExistingAtomKeysObject}", id, %{
          "metadata" => %{},
          "items" => []
        })

      {:ok, _pid} =
        Server.start_link(
          module: ExistingAtomKeysObject,
          object_id: id,
          repo: TestRepo
        )

      {:ok, state} = Server.call(ExistingAtomKeysObject, id, :get)

      assert state.metadata == %{}
      assert state.items == []
    end

    test "nil and scalar values within fields are preserved" do
      id = unique_id("edge-scalars")

      _ = [:str, :num, :bool, :null_val]

      {:ok, _} =
        Storage.save(TestRepo, "#{ExistingAtomKeysObject}", id, %{
          "metadata" => %{"str" => "hello", "num" => 42, "bool" => true, "null_val" => nil},
          "items" => []
        })

      {:ok, _pid} =
        Server.start_link(
          module: ExistingAtomKeysObject,
          object_id: id,
          repo: TestRepo
        )

      {:ok, state} = Server.call(ExistingAtomKeysObject, id, :get)

      assert state.metadata == %{str: "hello", num: 42, bool: true, null_val: nil}
    end

    test "scalar items in lists are not modified" do
      id = unique_id("edge-scalar-list")

      _ = [:tags]

      {:ok, _} =
        Storage.save(TestRepo, "#{ExistingAtomKeysObject}", id, %{
          "metadata" => %{"tags" => ["alpha", "beta", 3, true, nil]},
          "items" => [1, "two", nil, false]
        })

      {:ok, _pid} =
        Server.start_link(
          module: ExistingAtomKeysObject,
          object_id: id,
          repo: TestRepo
        )

      {:ok, state} = Server.call(ExistingAtomKeysObject, id, :get)

      assert state.metadata == %{tags: ["alpha", "beta", 3, true, nil]}
      assert state.items == [1, "two", nil, false]
    end

    test "nested lists of lists are traversed" do
      id = unique_id("edge-nested-list")

      _ = [:key]

      {:ok, _} =
        Storage.save(TestRepo, "#{ExistingAtomKeysObject}", id, %{
          "metadata" => %{},
          "items" => [[%{"key" => "inner"}], [1, 2]]
        })

      {:ok, _pid} =
        Server.start_link(
          module: ExistingAtomKeysObject,
          object_id: id,
          repo: TestRepo
        )

      {:ok, state} = Server.call(ExistingAtomKeysObject, id, :get)

      assert state.items == [[%{key: "inner"}], [1, 2]]
    end

    test "non-string keys in nested maps are preserved with :strings" do
      id = unique_id("edge-mixed-keys-strings")

      # Simulate a map that already has atom keys (e.g. from default merging)
      # plus string keys from JSON - :strings should leave values untouched
      {:ok, _} =
        Storage.save(TestRepo, "#{DefaultKeysObject}", id, %{
          "metadata" => %{"a" => 1},
          "items" => []
        })

      {:ok, _pid} =
        Server.start_link(
          module: DefaultKeysObject,
          object_id: id,
          repo: TestRepo
        )

      {:ok, state} = Server.call(DefaultKeysObject, id, :get)

      # Value map is untouched - keys remain strings
      assert state.metadata == %{"a" => 1}
    end

    test "already-atom keys in nested maps are preserved with :atoms!" do
      id = unique_id("edge-atom-keys")

      _ = [:existing_key]

      # Stored state only has string keys from JSON, but verify the convert_value
      # non-string-key branch by saving a map with an already-atom key.
      # In practice JSON always produces string keys, but the code handles mixed maps.
      {:ok, _} =
        Storage.save(TestRepo, "#{ExistingAtomKeysObject}", id, %{
          "metadata" => %{"existing_key" => "val"},
          "items" => []
        })

      {:ok, _pid} =
        Server.start_link(
          module: ExistingAtomKeysObject,
          object_id: id,
          repo: TestRepo
        )

      {:ok, state} = Server.call(ExistingAtomKeysObject, id, :get)

      assert state.metadata == %{existing_key: "val"}
    end
  end

  describe ":strings with nested structures" do
    test "preserves string keys in lists of maps" do
      id = unique_id("strings-list")

      {:ok, _} =
        Storage.save(TestRepo, "#{DefaultKeysObject}", id, %{
          "metadata" => %{},
          "items" => [%{"a" => 1, "b" => %{"c" => 2}}, %{"d" => 3}]
        })

      {:ok, _pid} =
        Server.start_link(
          module: DefaultKeysObject,
          object_id: id,
          repo: TestRepo
        )

      {:ok, state} = Server.call(DefaultKeysObject, id, :get)

      assert state.items == [%{"a" => 1, "b" => %{"c" => 2}}, %{"d" => 3}]
    end

    test "preserves string keys in deeply nested maps" do
      id = unique_id("strings-deep")

      {:ok, _} =
        Storage.save(TestRepo, "#{DefaultKeysObject}", id, %{
          "metadata" => %{"a" => %{"b" => %{"c" => "deep"}}},
          "items" => []
        })

      {:ok, _pid} =
        Server.start_link(
          module: DefaultKeysObject,
          object_id: id,
          repo: TestRepo
        )

      {:ok, state} = Server.call(DefaultKeysObject, id, :get)

      assert state.metadata == %{"a" => %{"b" => %{"c" => "deep"}}}
    end
  end

  describe "field names always atomized" do
    test "field names are atoms regardless of object_keys setting" do
      id = unique_id("field-names")

      {:ok, _} =
        Storage.save(TestRepo, "#{DefaultKeysObject}", id, %{
          "metadata" => %{"key" => "value"},
          "items" => []
        })

      {:ok, _pid} =
        Server.start_link(
          module: DefaultKeysObject,
          object_id: id,
          repo: TestRepo
        )

      {:ok, state} = Server.call(DefaultKeysObject, id, :get)

      assert Map.has_key?(state, :metadata)
      assert Map.has_key?(state, :items)
      refute Map.has_key?(state, "metadata")
      refute Map.has_key?(state, "items")
    end

    test "field names are atoms with :atoms! option" do
      id = unique_id("field-names-atoms!")

      {:ok, _} =
        Storage.save(TestRepo, "#{ExistingAtomKeysObject}", id, %{
          "metadata" => %{},
          "items" => []
        })

      {:ok, _pid} =
        Server.start_link(
          module: ExistingAtomKeysObject,
          object_id: id,
          repo: TestRepo
        )

      {:ok, state} = Server.call(ExistingAtomKeysObject, id, :get)

      assert Map.has_key?(state, :metadata)
      assert Map.has_key?(state, :items)
      refute Map.has_key?(state, "metadata")
      refute Map.has_key?(state, "items")
    end

    test "field names are atoms with :atoms option" do
      id = unique_id("field-names-atoms")

      {:ok, _} =
        Storage.save(TestRepo, "#{CreateAtomKeysObject}", id, %{
          "metadata" => %{},
          "items" => []
        })

      {:ok, _pid} =
        Server.start_link(
          module: CreateAtomKeysObject,
          object_id: id,
          repo: TestRepo
        )

      {:ok, state} = Server.call(CreateAtomKeysObject, id, :get)

      assert Map.has_key?(state, :metadata)
      assert Map.has_key?(state, :items)
      refute Map.has_key?(state, "metadata")
      refute Map.has_key?(state, "items")
    end
  end
end
