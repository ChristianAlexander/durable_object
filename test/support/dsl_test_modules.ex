# Test modules for DSL tests

defmodule DurableObject.DslTest.BasicCounter do
  use DurableObject.Dsl

  state do
    field(:count, :integer, default: 0)
  end

  handlers do
    handler(:increment, args: [:amount])
    handler(:get)
  end

  options do
    hibernate_after(300_000)
    shutdown_after(:timer.hours(1))
  end
end

defmodule DurableObject.DslTest.MinimalCounter do
  use DurableObject.Dsl

  state do
    field(:count, :integer)
  end

  handlers do
    handler(:get)
  end
end

defmodule DurableObject.DslTest.ChatRoom do
  use DurableObject.Dsl

  state do
    field(:messages, :list, default: [])
    field(:participants, :list, default: [])
    field(:created_at, :utc_datetime)
  end

  handlers do
    handler(:join, args: [:user_id])
    handler(:leave, args: [:user_id])
    handler(:send_message, args: [:user_id, :content])
    handler(:get_messages, args: [:limit])
    handler(:get_participants)
  end

  options do
    hibernate_after(:timer.minutes(10))
    shutdown_after(:timer.hours(2))
  end
end
