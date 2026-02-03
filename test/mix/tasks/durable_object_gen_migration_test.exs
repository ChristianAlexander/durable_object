defmodule Mix.Tasks.DurableObject.Gen.MigrationTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.DurableObject.Gen.Migration

  describe "info/2" do
    test "returns task info with correct schema" do
      info = Migration.info([], nil)

      assert info.group == :durable_object
      assert :repo in Keyword.keys(info.schema)
    end

    test "has correct example" do
      info = Migration.info([], nil)

      assert info.example =~ "mix durable_object.gen.migration"
    end
  end

  describe "extract_version_from_args/1" do
    test "returns :unversioned for empty args (no version specified)" do
      assert Migration.extract_version_from_args([]) == :unversioned
    end

    test "returns nil for unrecognized argument patterns" do
      assert Migration.extract_version_from_args(:invalid) == nil
      assert Migration.extract_version_from_args("string") == nil
    end

    test "extracts version from standard Elixir AST format" do
      # Standard AST format: {{:version, _, nil}, 2}
      args = [{{:version, [], nil}, 2}]
      assert Migration.extract_version_from_args([args]) == 2
    end

    test "extracts version from simple tuple format" do
      # Simple tuple format: {:version, 2}
      args = [{:version, 3}]
      assert Migration.extract_version_from_args([args]) == 3
    end

    test "extracts version from Sourceror wrapped AST format" do
      # Sourceror wraps AST nodes in {:__block__, metadata, [value]} tuples
      # This is the format produced when Igniter/Sourceror parses: version: 2
      args = [{{:__block__, [line: 1], [:version]}, {:__block__, [line: 1], [2]}}]
      assert Migration.extract_version_from_args([args]) == 2
    end

    test "extracts version from Sourceror wrapped AST with different metadata" do
      # Sourceror may include various metadata
      args = [
        {{:__block__, [trailing_comments: [], leading_comments: [], line: 5, column: 10],
          [:version]},
         {:__block__, [trailing_comments: [], leading_comments: [], line: 5, column: 20], [5]}}
      ]

      assert Migration.extract_version_from_args([args]) == 5
    end

    test "returns :unversioned when keyword list has no version key" do
      # Keyword list without version key
      args = [{{:__block__, [], [:base]}, {:__block__, [], [1]}}]
      assert Migration.extract_version_from_args([args]) == :unversioned
    end

    test "extracts version when multiple keywords are present (Sourceror format)" do
      # Migration with both base and version: up(base: 1, version: 3)
      args = [
        {{:__block__, [], [:base]}, {:__block__, [], [1]}},
        {{:__block__, [], [:version]}, {:__block__, [], [3]}}
      ]

      assert Migration.extract_version_from_args([args]) == 3
    end

    test "extracts version when multiple keywords are present (standard AST format)" do
      # Migration with both base and version: up(base: 1, version: 3)
      args = [
        {{:base, [], nil}, 1},
        {{:version, [], nil}, 3}
      ]

      assert Migration.extract_version_from_args([args]) == 3
    end

    test "only accepts integer versions" do
      # String version should not match
      args = [{{:__block__, [], [:version]}, {:__block__, [], ["2"]}}]
      assert Migration.extract_version_from_args([args]) == :unversioned

      # Atom version should not match
      args = [{{:__block__, [], [:version]}, {:__block__, [], [:v2]}}]
      assert Migration.extract_version_from_args([args]) == :unversioned
    end
  end
end
