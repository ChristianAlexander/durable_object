defmodule Mix.Tasks.DurableObject.InstallTest do
  use ExUnit.Case, async: true

  describe "info/2" do
    test "returns task info with correct schema" do
      info = Mix.Tasks.DurableObject.Install.info([], nil)

      assert info.group == :durable_object
      assert :repo in Keyword.keys(info.schema)
      assert :scheduler in Keyword.keys(info.schema)
      assert :oban_instance in Keyword.keys(info.schema)
      assert :oban_queue in Keyword.keys(info.schema)
      assert :distributed in Keyword.keys(info.schema)
    end

    test "has correct defaults" do
      info = Mix.Tasks.DurableObject.Install.info([], nil)

      assert info.defaults[:scheduler] == "polling"
      assert info.defaults[:oban_queue] == "durable_object_alarms"
      assert info.defaults[:distributed] == false
    end
  end
end
