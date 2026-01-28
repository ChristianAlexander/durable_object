defmodule DurableObject.Dsl.Handler do
  @moduledoc """
  Struct representing a handler (RPC method) in a Durable Object.

  Handlers define the operations that can be performed on the object:
  - `name` - The handler name (atom)
  - `args` - List of argument names (atoms)
  """

  defstruct [:name, args: [], __spark_metadata__: nil]

  @type t :: %__MODULE__{
          name: atom(),
          args: [atom()],
          __spark_metadata__: any()
        }
end
