defmodule DurableObject.Dsl.Transformers.BuildIntrospection do
  @moduledoc """
  Transformer that generates `__durable_object__/1` introspection functions.

  This transformer runs at compile time and generates functions that allow
  runtime introspection of the Durable Object's DSL configuration:

  - `__durable_object__(:fields)` - Returns list of Field structs
  - `__durable_object__(:handlers)` - Returns list of Handler structs
  - `__durable_object__(:hibernate_after)` - Returns hibernate_after value
  - `__durable_object__(:shutdown_after)` - Returns shutdown_after value
  - `__durable_object__(:default_state)` - Returns map with field defaults
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def transform(dsl_state) do
    fields = Transformer.get_entities(dsl_state, [:state])
    handlers = Transformer.get_entities(dsl_state, [:handlers])
    hibernate_after = Transformer.get_option(dsl_state, [:options], :hibernate_after) || 300_000
    shutdown_after = Transformer.get_option(dsl_state, [:options], :shutdown_after)

    # Build default state map from fields
    default_state =
      fields
      |> Enum.map(fn field -> {field.name, field.default} end)
      |> Map.new()

    # Persist values for later retrieval via Spark.Dsl.Extension.get_persisted/3
    dsl_state =
      dsl_state
      |> Transformer.persist(:durable_object_fields, fields)
      |> Transformer.persist(:durable_object_handlers, handlers)
      |> Transformer.persist(:durable_object_hibernate_after, hibernate_after)
      |> Transformer.persist(:durable_object_shutdown_after, shutdown_after)
      |> Transformer.persist(:durable_object_default_state, default_state)

    # Convert structs to a format that can be safely used in quoted expressions
    fields_data = Enum.map(fields, &Map.from_struct/1)
    handlers_data = Enum.map(handlers, &Map.from_struct/1)

    # Generate __durable_object__/1 functions
    dsl_state =
      Transformer.eval(
        dsl_state,
        [
          fields_data: fields_data,
          handlers_data: handlers_data,
          hibernate_after: hibernate_after,
          shutdown_after: shutdown_after,
          default_state: default_state
        ],
        quote do
          @doc false
          def __durable_object__(:fields) do
            Enum.map(unquote(Macro.escape(fields_data)), fn data ->
              struct(DurableObject.Dsl.Field, data)
            end)
          end

          def __durable_object__(:handlers) do
            Enum.map(unquote(Macro.escape(handlers_data)), fn data ->
              struct(DurableObject.Dsl.Handler, data)
            end)
          end

          def __durable_object__(:hibernate_after), do: unquote(hibernate_after)
          def __durable_object__(:shutdown_after), do: unquote(shutdown_after)
          def __durable_object__(:default_state), do: unquote(Macro.escape(default_state))
        end
      )

    {:ok, dsl_state}
  end

  @impl true
  def after?(DurableObject.Dsl.Transformers.GenerateClient), do: false
  def after?(_), do: true
end
