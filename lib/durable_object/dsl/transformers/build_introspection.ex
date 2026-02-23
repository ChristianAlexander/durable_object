defmodule DurableObject.Dsl.Transformers.BuildIntrospection do
  @moduledoc """
  Transformer that generates `__durable_object__/1` introspection functions
  and a nested `State` struct.

  This transformer runs at compile time and generates:

  - A `State` struct with fields and defaults from the DSL
  - `__durable_object__(:fields)` - Returns list of Field structs
  - `__durable_object__(:handlers)` - Returns list of Handler structs
  - `__durable_object__(:hibernate_after)` - Returns hibernate_after value
  - `__durable_object__(:shutdown_after)` - Returns shutdown_after value
  - `__durable_object__(:default_state)` - Returns `%__MODULE__.State{}` struct
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def transform(dsl_state) do
    fields = Transformer.get_entities(dsl_state, [:state])
    handlers = Transformer.get_entities(dsl_state, [:handlers])
    hibernate_after = Transformer.get_option(dsl_state, [:options], :hibernate_after) || 300_000
    shutdown_after = Transformer.get_option(dsl_state, [:options], :shutdown_after)
    object_keys = Transformer.get_option(dsl_state, [:options], :object_keys)

    # Build defstruct keyword list from fields (field_name => default)
    struct_fields =
      Enum.map(fields, fn field -> {field.name, field.default} end)

    # Build default state map from fields (for persisted data compatibility)
    default_state = Map.new(struct_fields)

    # Persist values for later retrieval via Spark.Dsl.Extension.get_persisted/3
    dsl_state =
      dsl_state
      |> Transformer.persist(:durable_object_fields, fields)
      |> Transformer.persist(:durable_object_handlers, handlers)
      |> Transformer.persist(:durable_object_hibernate_after, hibernate_after)
      |> Transformer.persist(:durable_object_shutdown_after, shutdown_after)
      |> Transformer.persist(:durable_object_default_state, default_state)
      |> Transformer.persist(:durable_object_object_keys, object_keys)

    # Convert structs to a format that can be safely used in quoted expressions
    fields_data = Enum.map(fields, &Map.from_struct/1)
    handlers_data = Enum.map(handlers, &Map.from_struct/1)

    # Generate nested State struct module
    dsl_state =
      Transformer.eval(
        dsl_state,
        [struct_fields: struct_fields],
        quote do
          defmodule State do
            @moduledoc false
            defstruct unquote(Macro.escape(struct_fields))
          end
        end
      )

    # Generate __durable_object__/1 functions
    dsl_state =
      Transformer.eval(
        dsl_state,
        [
          fields_data: fields_data,
          handlers_data: handlers_data,
          hibernate_after: hibernate_after,
          shutdown_after: shutdown_after,
          object_keys: object_keys
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
          def __durable_object__(:default_state), do: %__MODULE__.State{}
          def __durable_object__(:object_keys), do: unquote(object_keys)
        end
      )

    {:ok, dsl_state}
  end

  @impl true
  def after?(DurableObject.Dsl.Transformers.GenerateClient), do: false
  def after?(_), do: true
end
