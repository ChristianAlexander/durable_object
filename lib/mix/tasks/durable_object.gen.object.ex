if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.DurableObject.Gen.Object do
    @moduledoc """
    Generates a new Durable Object module.

    ## Usage

        mix durable_object.gen.object MyApp.Counter --fields count:integer
        mix durable_object.gen.object MyApp.RateLimiter --fields requests:integer,window_start:utc_datetime

    ## Options

    * `--fields` - Comma-separated list of field:type pairs
    * `--repo` - The Ecto repo to use (defaults to auto-detected repo)

    ## Supported Field Types

    | Type | Default |
    |------|---------|
    | `integer` | `0` |
    | `float` | `0.0` |
    | `string` | `""` |
    | `boolean` | `false` |
    | `map` | `%{}` |
    | `list` | `[]` |
    | `utc_datetime` | `nil` |
    | `naive_datetime` | `nil` |

    Any unrecognized type defaults to `nil`.

    ## Examples

        mix durable_object.gen.object MyApp.Counter --fields count:integer
        mix durable_object.gen.object MyApp.ChatRoom --fields messages:list,participants:list
    """

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :durable_object,
        example: "mix durable_object.gen.object MyApp.Counter --fields count:integer",
        positional: [:module_name],
        schema: [
          fields: :string,
          repo: :string
        ]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      %{module_name: module_name} = igniter.args.positional
      options = igniter.args.options

      module = Module.concat([module_name])
      fields = parse_fields(options[:fields] || "")

      module_content = generate_module(module, fields)
      path = Igniter.Project.Module.proper_location(igniter, module)

      Igniter.create_new_file(igniter, path, module_content)
    end

    defp parse_fields(""), do: []

    defp parse_fields(fields_string) do
      fields_string
      |> String.split(",", trim: true)
      |> Enum.map(fn field ->
        case String.split(field, ":", parts: 2) do
          [name, type] ->
            {String.to_atom(String.trim(name)), String.to_atom(String.trim(type))}

          [name] ->
            {String.to_atom(String.trim(name)), :any}
        end
      end)
    end

    defp generate_module(module, fields) do
      fields_code =
        if fields == [] do
          "# field :name, :type, default: value"
        else
          Enum.map_join(fields, "\n    ", fn {name, type} ->
            default = default_for_type(type)
            "field :#{name}, :#{type}, default: #{inspect(default)}"
          end)
        end

      """
      defmodule #{inspect(module)} do
        @moduledoc \"\"\"
        A Durable Object for #{module |> Module.split() |> List.last()}.

        ## Usage

            # Start interacting with the object by ID
            {:ok, result} = #{inspect(module)}.my_handler("object-id", args)
        \"\"\"

        use DurableObject

        state do
          #{fields_code}
        end

        handlers do
          # Define your handlers here:
          # handler :my_handler, args: [:arg1, :arg2]
        end

        # Implement your handlers here:
        #
        # def handle_my_handler(arg1, arg2, state) do
        #   # Process the request and update state
        #   {:reply, result, new_state}
        # end
      end
      """
    end

    defp default_for_type(:integer), do: 0
    defp default_for_type(:float), do: 0.0
    defp default_for_type(:string), do: ""
    defp default_for_type(:boolean), do: false
    defp default_for_type(:map), do: %{}
    defp default_for_type(:list), do: []
    defp default_for_type(:utc_datetime), do: nil
    defp default_for_type(:naive_datetime), do: nil
    defp default_for_type(_), do: nil
  end
end
