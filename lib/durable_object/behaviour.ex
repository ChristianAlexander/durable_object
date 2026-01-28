defmodule DurableObject.Behaviour do
  @moduledoc """
  Behaviour for Durable Object alarm handling.

  Defines the optional `handle_alarm/2` callback for processing scheduled alarms.

  ## Handler Callbacks

  For each handler declared in the DSL:

      handlers do
        handler :increment, args: [:amount]
        handler :get
      end

  You must implement a corresponding `handle_<name>/N` function where N is
  the number of args plus 1 (for state):

      def handle_increment(amount, state) do
        new_count = state.count + amount
        {:reply, new_count, %{state | count: new_count}}
      end

      def handle_get(state) do
        {:reply, state.count, state}
      end

  ## Handler Return Values

  Handlers can return:

  - `{:reply, result, new_state}` - Reply with result
  - `{:reply, result, new_state, {:schedule_alarm, name, delay_ms}}` - Reply and schedule alarm
  - `{:noreply, new_state}` - No reply (for async operations)
  - `{:noreply, new_state, {:schedule_alarm, name, delay_ms}}` - No reply and schedule alarm
  - `{:error, reason}` - Return an error

  ## Alarm Callback

  To handle scheduled alarms, implement `handle_alarm/2`:

      def handle_alarm(:daily_reset, state) do
        # Reschedule for tomorrow
        {:noreply, %{state | count: 0}, {:schedule_alarm, :daily_reset, :timer.hours(24)}}
      end

  This is optional - if not defined, alarms are silently acknowledged.
  """

  @type handler_result ::
          {:reply, result :: term(), new_state :: map()}
          | {:reply, result :: term(), new_state :: map(),
             {:schedule_alarm, name :: atom(), delay_ms :: pos_integer()}}
          | {:noreply, new_state :: map()}
          | {:noreply, new_state :: map(),
             {:schedule_alarm, name :: atom(), delay_ms :: pos_integer()}}
          | {:error, reason :: term()}

  @type alarm_result ::
          {:noreply, new_state :: map()}
          | {:noreply, new_state :: map(),
             {:schedule_alarm, name :: atom(), delay_ms :: pos_integer()}}
          | {:error, reason :: term()}

  @doc """
  Called when a scheduled alarm fires.

  This callback is optional. If not defined, alarms are silently acknowledged.
  """
  @callback handle_alarm(alarm_name :: atom(), state :: map()) :: alarm_result()

  @optional_callbacks [handle_alarm: 2]
end
