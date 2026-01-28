defmodule DurableObject.Dsl do
  @moduledoc """
  Spark DSL for defining Durable Objects.

  This is the base module for defining Durable Object DSLs. Use this when defining
  a Durable Object module:

      defmodule MyApp.Counter do
        use DurableObject.Dsl

        state do
          field :count, :integer, default: 0
        end

        handlers do
          handler :increment, args: [:amount]
          handler :get
        end

        options do
          hibernate_after 300_000
        end
      end

  ## Sections

  ### state

  Define the state fields for the Durable Object:

      state do
        field :count, :integer, default: 0
        field :name, :string
      end

  ### handlers

  Define the handlers (RPC methods) for the Durable Object:

      handlers do
        handler :increment, args: [:amount]
        handler :get
      end

  ### options

  Configure lifecycle options:

      options do
        hibernate_after 300_000
        shutdown_after :timer.hours(1)
      end
  """

  use Spark.Dsl,
    default_extensions: [
      extensions: [DurableObject.Dsl.Extension]
    ]
end
