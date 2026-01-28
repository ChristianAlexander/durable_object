defmodule DurableObject.Dsl.Transformers.GenerateClient do
  @moduledoc """
  Transformer that generates client API functions for each declared handler.

  For each handler declared in the DSL, this generates a client function
  that calls `DurableObject.call/5` with the appropriate arguments.

  For example, given:

      handlers do
        handler :increment, args: [:amount]
        handler :get
      end

  This generates:

      def increment(object_id, amount, opts \\\\ []) do
        DurableObject.call(__MODULE__, object_id, :increment, [amount], opts)
      end

      def get(object_id, opts \\\\ []) do
        DurableObject.call(__MODULE__, object_id, :get, [], opts)
      end
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def transform(dsl_state) do
    handlers = Transformer.get_entities(dsl_state, [:handlers])

    dsl_state =
      Enum.reduce(handlers, dsl_state, fn handler, dsl_state ->
        generate_client_function(dsl_state, handler)
      end)

    {:ok, dsl_state}
  end

  @impl true
  def after?(DurableObject.Dsl.Transformers.BuildIntrospection), do: true
  def after?(_), do: false

  defp generate_client_function(dsl_state, handler) do
    handler_name = handler.name
    args = handler.args

    # Build the AST for the function arguments
    arg_vars =
      Enum.map(args, fn arg ->
        Macro.var(arg, nil)
      end)

    # Build the list of argument values to pass to DurableObject.call
    args_list =
      Enum.map(args, fn arg ->
        Macro.var(arg, nil)
      end)

    Transformer.eval(
      dsl_state,
      [
        handler_name: handler_name,
        arg_vars: arg_vars,
        args_list: args_list
      ],
      if args == [] do
        quote do
          @doc """
          Calls the `#{unquote(handler_name)}` handler on the object with the given ID.

          ## Options

            * `:repo` - Ecto repo for persistence
            * `:prefix` - Table prefix for multi-tenancy
            * `:timeout` - Call timeout in ms (default: 5000)

          ## Returns

            * `{:ok, result}` - Handler returned `{:reply, result, new_state}`
            * `{:ok, :noreply}` - Handler returned `{:noreply, new_state}`
            * `{:error, reason}` - Error occurred
          """
          def unquote(handler_name)(object_id, opts \\ []) do
            DurableObject.call(__MODULE__, object_id, unquote(handler_name), [], opts)
          end
        end
      else
        quote do
          @doc """
          Calls the `#{unquote(handler_name)}` handler on the object with the given ID.

          ## Arguments

          #{unquote(format_args_doc(args))}

          ## Options

            * `:repo` - Ecto repo for persistence
            * `:prefix` - Table prefix for multi-tenancy
            * `:timeout` - Call timeout in ms (default: 5000)

          ## Returns

            * `{:ok, result}` - Handler returned `{:reply, result, new_state}`
            * `{:ok, :noreply}` - Handler returned `{:noreply, new_state}`
            * `{:error, reason}` - Error occurred
          """
          def unquote(handler_name)(object_id, unquote_splicing(arg_vars), opts \\ []) do
            DurableObject.call(
              __MODULE__,
              object_id,
              unquote(handler_name),
              unquote(args_list),
              opts
            )
          end
        end
      end
    )
  end

  defp format_args_doc(args) do
    args
    |> Enum.map(fn arg -> "  * `#{arg}`" end)
    |> Enum.join("\n")
  end
end
