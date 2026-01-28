defmodule DurableObject.Dsl.Verifiers.ValidateHandlers do
  @moduledoc """
  Verifier that validates handler callbacks are properly defined.

  This verifier checks that:
  - Each declared handler has a corresponding `handle_<name>/N` function defined
  - The function arity matches: number of declared args + 1 (for state)

  For example, a handler declared as:

      handler :increment, args: [:amount]

  Must have a corresponding function:

      def handle_increment(amount, state) do
        ...
      end
  """

  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    handlers = Verifier.get_persisted(dsl_state, :durable_object_handlers) || []

    errors =
      handlers
      |> Enum.reject(fn handler ->
        handler_fn = :"handle_#{handler.name}"
        expected_arity = length(handler.args) + 1

        function_exported?(module, handler_fn, expected_arity)
      end)
      |> Enum.map(fn handler ->
        handler_fn = :"handle_#{handler.name}"
        expected_arity = length(handler.args) + 1

        %Spark.Error.DslError{
          module: module,
          path: [:handlers, :handler],
          message: """
          Handler `#{handler.name}` is declared but `#{handler_fn}/#{expected_arity}` is not defined.

          Expected function signature:

              def #{handler_fn}(#{format_args(handler.args)}) do
                # Handler implementation
                {:reply, result, new_state}
              end
          """
        }
      end)

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp format_args([]), do: "state"

  defp format_args(args) do
    args_str =
      args
      |> Enum.map(&to_string/1)
      |> Enum.join(", ")

    "#{args_str}, state"
  end
end
