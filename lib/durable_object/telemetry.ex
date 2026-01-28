defmodule DurableObject.Telemetry do
  @moduledoc """
  Telemetry instrumentation for DurableObject.

  This module provides helpers for emitting telemetry events during storage operations.

  ## Events

  All events are prefixed with `[:durable_object, :storage, <operation>]` where operation
  is one of: `:save`, `:load`, `:delete`.

  Each operation emits three events:
  - `[:durable_object, :storage, <operation>, :start]` - Emitted when the operation begins
  - `[:durable_object, :storage, <operation>, :stop]` - Emitted when the operation completes successfully
  - `[:durable_object, :storage, <operation>, :exception]` - Emitted when the operation raises an exception

  ### Start Event Measurements
  - `:system_time` - The system time when the operation started (in native units)

  ### Stop Event Measurements
  - `:duration` - The duration of the operation (in native units)

  ### Exception Event Measurements
  - `:duration` - The duration until the exception occurred (in native units)

  ### Metadata (all events)
  - `:object_type` - The type of the durable object
  - `:object_id` - The ID of the durable object
  - `:repo` - The Ecto repo module

  ### Additional Exception Metadata
  - `:kind` - The kind of exception (`:error`, `:exit`, `:throw`)
  - `:reason` - The exception or error reason
  - `:stacktrace` - The stacktrace at the time of the exception

  ## Example

  To attach a handler:

      :telemetry.attach_many(
        "my-handler",
        [
          [:durable_object, :storage, :save, :start],
          [:durable_object, :storage, :save, :stop],
          [:durable_object, :storage, :save, :exception]
        ],
        &MyModule.handle_event/4,
        nil
      )

  """

  @doc """
  Executes a function within a telemetry span.

  Emits `:start`, `:stop`, and `:exception` events with the given event prefix.
  Returns `{:ok, result}` on success or `{:error, {:operation_failed, exception}}` on failure.

  ## Parameters

  - `event_prefix` - List of atoms for the event prefix, e.g., `[:durable_object, :storage, :save]`
  - `metadata` - Map of metadata to include in all events
  - `fun` - Zero-arity function to execute

  ## Returns

  - `{:ok, result}` - The function completed successfully with `result`
  - `{:error, {failure_type, exception}}` - The function raised an exception

  """
  @spec span(list(atom()), map(), (-> term())) ::
          {:ok, term()} | {:error, {atom(), Exception.t()}}
  def span(event_prefix, metadata, fun)
      when is_list(event_prefix) and is_map(metadata) and is_function(fun, 0) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      event_prefix ++ [:start],
      %{system_time: System.system_time()},
      metadata
    )

    try do
      result = fun.()

      :telemetry.execute(
        event_prefix ++ [:stop],
        %{duration: System.monotonic_time() - start_time},
        metadata
      )

      {:ok, result}
    rescue
      exception ->
        stacktrace = __STACKTRACE__

        :telemetry.execute(
          event_prefix ++ [:exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(metadata, %{
            kind: :error,
            reason: exception,
            stacktrace: stacktrace
          })
        )

        {:error, exception}
    catch
      kind, reason ->
        stacktrace = __STACKTRACE__

        :telemetry.execute(
          event_prefix ++ [:exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(metadata, %{
            kind: kind,
            reason: reason,
            stacktrace: stacktrace
          })
        )

        {:error, {kind, reason}}
    end
  end
end
