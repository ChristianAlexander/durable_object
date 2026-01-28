defmodule DurableObject.Dsl.Extension do
  @moduledoc """
  Spark DSL extension defining the structure for Durable Objects.

  This extension provides three sections:

  - `state` - Define state fields
  - `handlers` - Define RPC handlers
  - `options` - Configure lifecycle options
  """

  @field %Spark.Dsl.Entity{
    name: :field,
    args: [:name, :type],
    target: DurableObject.Dsl.Field,
    describe: "A field in the Durable Object's state",
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the field"
      ],
      type: [
        type: :atom,
        required: true,
        doc: "The type of the field (for documentation)"
      ],
      default: [
        type: :any,
        doc: "The default value for the field"
      ]
    ]
  }

  @handler %Spark.Dsl.Entity{
    name: :handler,
    args: [:name],
    target: DurableObject.Dsl.Handler,
    describe: "An RPC handler for the Durable Object",
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the handler"
      ],
      args: [
        type: {:list, :atom},
        default: [],
        doc: "List of argument names for the handler"
      ]
    ]
  }

  @state_section %Spark.Dsl.Section{
    name: :state,
    describe: "Define the state fields for this Durable Object",
    entities: [@field]
  }

  @handlers_section %Spark.Dsl.Section{
    name: :handlers,
    describe: "Define the handlers (RPC methods) for this Durable Object",
    entities: [@handler]
  }

  @options_section %Spark.Dsl.Section{
    name: :options,
    describe: "Configure lifecycle options",
    schema: [
      hibernate_after: [
        type: {:or, [:pos_integer, {:literal, :infinity}]},
        default: 300_000,
        doc: "Hibernate process after this many ms of inactivity (default: 5 minutes)"
      ],
      shutdown_after: [
        type: {:or, [:pos_integer, {:literal, :infinity}, nil]},
        default: nil,
        doc: "Stop process after this many ms of inactivity (nil = never)"
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@state_section, @handlers_section, @options_section],
    transformers: [
      DurableObject.Dsl.Transformers.BuildIntrospection
    ],
    verifiers: [
      DurableObject.Dsl.Verifiers.ValidateHandlers
    ]
end
