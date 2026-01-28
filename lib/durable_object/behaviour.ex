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

  @type after_load_result ::
          {:ok, new_state :: map()}
          | {:ok, new_state :: map(),
             {:schedule_alarm, name :: atom(), delay_ms :: pos_integer()}}

  @doc """
  Called when a scheduled alarm fires.

  This callback is optional. If not defined, alarms are silently acknowledged.
  """
  @callback handle_alarm(alarm_name :: atom(), state :: map()) :: alarm_result()

  @doc """
  Called after object state is loaded (or initialized with defaults for new objects).

  Use this to schedule initial alarms or perform one-time setup.

  This callback is optional. If not defined, no action is taken after load.

  ## Example

      def after_load(state) do
        if is_nil(state.window_start) do
          {:ok, %{state | window_start: DateTime.utc_now()},
           {:schedule_alarm, :reset_window, :timer.minutes(1)}}
        else
          {:ok, state}
        end
      end
  """
  @callback after_load(state :: map()) :: after_load_result()

  @optional_callbacks [handle_alarm: 2, after_load: 1]
end
