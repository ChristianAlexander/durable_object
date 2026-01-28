defmodule DurableObject.DslTest do
  use ExUnit.Case, async: true

  alias DurableObject.DslTest.{BasicCounter, MinimalCounter, ChatRoom}

  describe "DSL parsing" do
    test "parses state fields" do
      fields = Spark.Dsl.Extension.get_entities(BasicCounter, [:state])

      assert length(fields) == 1
      [count_field] = fields
      assert count_field.name == :count
      assert count_field.type == :integer
      assert count_field.default == 0
    end

    test "parses handlers" do
      handlers = Spark.Dsl.Extension.get_entities(BasicCounter, [:handlers])

      assert length(handlers) == 2

      increment_handler = Enum.find(handlers, &(&1.name == :increment))
      assert increment_handler.args == [:amount]

      get_handler = Enum.find(handlers, &(&1.name == :get))
      assert get_handler.args == []
    end

    test "parses options" do
      hibernate_after = Spark.Dsl.Extension.get_opt(BasicCounter, [:options], :hibernate_after)
      shutdown_after = Spark.Dsl.Extension.get_opt(BasicCounter, [:options], :shutdown_after)

      assert hibernate_after == 300_000
      assert shutdown_after == :timer.hours(1)
    end
  end

  describe "DSL defaults" do
    test "returns nil when options section not specified" do
      # When the options section isn't specified, get_opt returns nil
      hibernate_after = Spark.Dsl.Extension.get_opt(MinimalCounter, [:options], :hibernate_after)
      assert hibernate_after == nil
    end

    test "can provide fallback default when options section not specified" do
      # Use get_opt with a default value for modules that don't specify options
      hibernate_after =
        Spark.Dsl.Extension.get_opt(MinimalCounter, [:options], :hibernate_after, 300_000)

      assert hibernate_after == 300_000
    end

    test "uses schema default for shutdown_after when options section not specified" do
      shutdown_after = Spark.Dsl.Extension.get_opt(MinimalCounter, [:options], :shutdown_after)
      assert shutdown_after == nil
    end

    test "field default is nil when not specified" do
      [field] = Spark.Dsl.Extension.get_entities(MinimalCounter, [:state])
      assert field.default == nil
    end
  end

  describe "multiple fields" do
    test "parses multiple state fields" do
      fields = Spark.Dsl.Extension.get_entities(ChatRoom, [:state])
      assert length(fields) == 3

      messages_field = Enum.find(fields, &(&1.name == :messages))
      assert messages_field.type == :list
      assert messages_field.default == []

      participants_field = Enum.find(fields, &(&1.name == :participants))
      assert participants_field.type == :list
      assert participants_field.default == []

      created_at_field = Enum.find(fields, &(&1.name == :created_at))
      assert created_at_field.type == :utc_datetime
      assert created_at_field.default == nil
    end

    test "parses multiple handlers with various arities" do
      handlers = Spark.Dsl.Extension.get_entities(ChatRoom, [:handlers])
      assert length(handlers) == 5

      join_handler = Enum.find(handlers, &(&1.name == :join))
      assert join_handler.args == [:user_id]

      send_message_handler = Enum.find(handlers, &(&1.name == :send_message))
      assert send_message_handler.args == [:user_id, :content]

      get_participants_handler = Enum.find(handlers, &(&1.name == :get_participants))
      assert get_participants_handler.args == []
    end
  end
end
