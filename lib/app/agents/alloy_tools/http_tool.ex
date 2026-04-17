defmodule App.Agents.AlloyTools.HttpTool do
  @moduledoc """
  Dynamically wraps a user-defined `App.Tools.Tool` HTTP tool
  as an Alloy-compatible tool definition for runtime use.

  Since Alloy tools are normally modules implementing the `Alloy.Tool`
  behaviour, this module provides a struct-based approach that can be
  included in the tools list alongside behaviour modules.
  """

  alias App.Tools.Tool

  defstruct [:name, :description, :input_schema, :tool]

  @doc """
  Build an Alloy-compatible tool struct from a `Tool` record.
  """
  def from_tool(%Tool{} = tool) do
    %__MODULE__{
      name: tool.name,
      description: tool.description,
      input_schema: runtime_parameter_schema(tool),
      tool: tool
    }
  end

  def execute(%__MODULE__{tool: tool}, args) do
    App.Agents.Tools.execute_http_tool(tool, args)
  end

  defp runtime_parameter_schema(%Tool{} = tool) do
    properties =
      tool
      |> Tool.runtime_param_items()
      |> Enum.reduce(%{}, fn item, acc ->
        Map.put(acc, Map.fetch!(item, "name"), %{
          "type" => json_schema_type(Map.fetch!(item, "type")),
          "description" => "Runtime value for #{Map.fetch!(item, "name")}"
        })
      end)

    required = Enum.map(Tool.runtime_param_items(tool), &Map.fetch!(&1, "name"))

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
