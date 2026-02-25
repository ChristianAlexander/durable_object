defmodule DurableObject.Dsl.Verifiers.ValidateFields do
  @moduledoc """
  Verifier that validates field names in the state block.

  Checks that user-declared fields do not conflict with built-in field names
  (e.g., `:id` is injected automatically and cannot be redeclared).
  """

  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier

  @reserved_fields [:id]

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    fields = Verifier.get_persisted(dsl_state, :durable_object_fields) || []

    errors =
      fields
      |> Enum.filter(fn field -> field.name in @reserved_fields end)
      |> Enum.map(fn field ->
        %Spark.Error.DslError{
          module: module,
          path: [:state, :field],
          message:
            "Field name `#{field.name}` is reserved. " <>
              "The `#{field.name}` field is built-in and automatically available on the state."
        }
      end)

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end
end
