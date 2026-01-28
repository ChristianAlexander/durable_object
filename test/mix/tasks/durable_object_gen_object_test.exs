defmodule Mix.Tasks.DurableObject.Gen.ObjectTest do
  use ExUnit.Case, async: true

  describe "info/2" do
    test "returns task info with correct schema" do
      info = Mix.Tasks.DurableObject.Gen.Object.info([], nil)

      assert info.group == :durable_object
      assert info.positional == [:module_name]
      assert :fields in Keyword.keys(info.schema)
      assert :repo in Keyword.keys(info.schema)
    end

    test "has correct example" do
      info = Mix.Tasks.DurableObject.Gen.Object.info([], nil)

      assert info.example =~ "mix durable_object.gen.object"
      assert info.example =~ "MyApp.Counter"
    end
  end

  describe "field parsing" do
    # We can't easily test private functions, but we can test the generated output
    # through integration tests if needed
  end
end
