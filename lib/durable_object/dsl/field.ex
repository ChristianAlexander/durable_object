defmodule DurableObject.Dsl.Field do
  @moduledoc """
  Struct representing a state field in a Durable Object.

  Fields define the structure of the object's state, including:
  - `name` - The field name (atom)
  - `type` - The field type (atom, for documentation purposes)
  - `default` - The default value for the field
  """

  defstruct [:name, :type, :default, :__spark_metadata__]

  @type t :: %__MODULE__{
          name: atom(),
          type: atom(),
          default: any(),
          __spark_metadata__: any()
        }
end
