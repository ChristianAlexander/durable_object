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

  # Handler implementations
  def handle_increment(amount, state) do
    new_count = Map.get(state, :count, 0) + amount
    {:reply, new_count, %{state | count: new_count}}
  end

  def handle_get(state) do
    {:reply, state.count, state}
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

  # Handler implementation
  def handle_get(state) do
    {:reply, state.count, state}
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

  # Handler implementations
  def handle_join(user_id, state) do
    if user_id in state.participants do
      {:error, :already_joined}
    else
      {:reply, :ok, %{state | participants: [user_id | state.participants]}}
    end
  end

  def handle_leave(user_id, state) do
    {:reply, :ok, %{state | participants: List.delete(state.participants, user_id)}}
  end

  def handle_send_message(user_id, content, state) do
    message = %{user_id: user_id, content: content, timestamp: DateTime.utc_now()}
    {:reply, {:ok, message}, %{state | messages: [message | state.messages]}}
  end

  def handle_get_messages(limit, state) do
    {:reply, Enum.take(state.messages, limit), state}
  end

  def handle_get_participants(state) do
    {:reply, state.participants, state}
  end
end
