defmodule App.Agents.AlloyTools.HttpTool do
  @moduledoc """
  Builds Alloy-compatible runtime modules for user-defined HTTP tools.
  """

  alias App.Tools.Tool

  defstruct [:name, :description, :input_schema, :tool]

  @doc """
  Build an Alloy-compatible tool module from a `Tool` record.
  """
  def from_tool(%Tool{} = tool) do
    module = module_name(tool)

    unless Code.ensure_loaded?(module) do
      {:module, ^module, _binary, _exports} =
        Module.create(module, runtime_module_quoted(tool), Macro.Env.location(__ENV__))
    end

    module
  end

  def execute(%__MODULE__{tool: tool}, args) do
    App.Agents.Tools.execute_http_tool(tool, args)
  end

  defp module_name(%Tool{} = tool) do
    signature =
      tool
      |> tool_signature()
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    Module.concat([__MODULE__, "Tool_#{signature}"])
  end

  defp tool_signature(%Tool{} = tool) do
    %{
      id: tool.id,
      updated_at: tool.updated_at,
      name: tool.name,
      description: tool.description,
      endpoint: tool.endpoint,
      http_method: tool.http_method,
      parameter_definitions: tool.parameter_definitions,
      static_headers: tool.static_headers
    }
  end

  defp runtime_module_quoted(%Tool{} = tool) do
    tool_ast = Macro.escape(tool)

    quote do
      @behaviour Alloy.Tool
      @tool unquote(tool_ast)

      @impl true
      def name, do: @tool.name

      @impl true
      def description, do: @tool.description

      @impl true
      def input_schema, do: runtime_parameter_schema(@tool)

      @impl true
      def execute(input, _context), do: App.Agents.Tools.execute_http_tool(@tool, input)

      defp runtime_parameter_schema(%App.Tools.Tool{} = tool) do
        properties =
          tool
          |> App.Tools.Tool.runtime_param_items()
          |> Enum.reduce(%{}, fn item, acc ->
            Map.put(acc, Map.fetch!(item, "name"), %{
              "type" => json_schema_type(Map.fetch!(item, "type")),
              "description" => "Runtime value for #{Map.fetch!(item, "name")}"
            })
          end)

        required = Enum.map(App.Tools.Tool.runtime_param_items(tool), &Map.fetch!(&1, "name"))

        %{
          "type" => "object",
          "properties" => properties,
          "required" => required
        }
      end

      @supported_param_types %{
        "string" => "string",
        "integer" => "integer",
        "number" => "number",
        "boolean" => "boolean"
      }

      defp json_schema_type(type), do: Map.fetch!(@supported_param_types, type)
    end
  end
end
