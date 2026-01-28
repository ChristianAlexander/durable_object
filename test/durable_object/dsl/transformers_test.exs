defmodule DurableObject.Dsl.TransformersTest do
  use ExUnit.Case, async: true

  alias DurableObject.DslTest.{BasicCounter, MinimalCounter, ChatRoom}
  alias DurableObject.Dsl.{Field, Handler}

  describe "BuildIntrospection transformer" do
    test "generates __durable_object__(:fields)" do
      fields = BasicCounter.__durable_object__(:fields)

      assert length(fields) == 1
      [count_field] = fields
      assert %Field{name: :count, type: :integer, default: 0} = count_field
    end

    test "generates __durable_object__(:handlers)" do
      handlers = BasicCounter.__durable_object__(:handlers)

      assert length(handlers) == 2
      increment_handler = Enum.find(handlers, &(&1.name == :increment))
      assert %Handler{name: :increment, args: [:amount]} = increment_handler

      get_handler = Enum.find(handlers, &(&1.name == :get))
      assert %Handler{name: :get, args: []} = get_handler
    end

    test "generates __durable_object__(:hibernate_after)" do
      assert BasicCounter.__durable_object__(:hibernate_after) == 300_000
    end

    test "generates __durable_object__(:shutdown_after)" do
      assert BasicCounter.__durable_object__(:shutdown_after) == :timer.hours(1)
    end

    test "generates __durable_object__(:default_state)" do
      default_state = BasicCounter.__durable_object__(:default_state)
      assert default_state == %{count: 0}
    end

    test "uses default hibernate_after when not specified" do
      # MinimalCounter doesn't specify options, so should get default
      assert MinimalCounter.__durable_object__(:hibernate_after) == 300_000
    end

    test "uses nil shutdown_after when not specified" do
      assert MinimalCounter.__durable_object__(:shutdown_after) == nil
    end

    test "handles multiple fields in default_state" do
      default_state = ChatRoom.__durable_object__(:default_state)

      assert default_state == %{
               messages: [],
               participants: [],
               created_at: nil
             }
    end

    test "handles multiple handlers" do
      handlers = ChatRoom.__durable_object__(:handlers)

      assert length(handlers) == 5

      handler_names = Enum.map(handlers, & &1.name)
      assert :join in handler_names
      assert :leave in handler_names
      assert :send_message in handler_names
      assert :get_messages in handler_names
      assert :get_participants in handler_names
    end

    test "preserves handler args" do
      handlers = ChatRoom.__durable_object__(:handlers)

      send_message = Enum.find(handlers, &(&1.name == :send_message))
      assert send_message.args == [:user_id, :content]

      get_participants = Enum.find(handlers, &(&1.name == :get_participants))
      assert get_participants.args == []
    end
  end
end
