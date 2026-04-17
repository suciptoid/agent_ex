defmodule App.Agents.AlloyTools.CreateTool do
  @moduledoc false
  @behaviour Alloy.Tool

  alias App.Tools.Tool

  @impl true
  def name, do: "create_tool"

  @impl true
  def description,
    do:
      "Create and save a reusable HTTP tool for the current organization using the same fields as the tools UI."

  @impl true
  def input_schema do
    %{
      type: "object",
      properties: %{
        name: %{
          type: "string",
          description: "Tool identifier, for example brave_search"
        },
        description: %{
          type: "string",
          description: "Short sentence explaining what the tool does"
        },
        endpoint: %{
          type: "string",
          description:
            "HTTP URL template, including any placeholders like https://api.example.com/{path}"
        },
        http_method: %{
          type: "string",
          description: "HTTP method for the saved tool",
          enum: Tool.http_methods()
        },
        param_rows: %{
          type: "array",
          description:
            "Tool parameters. Leave value blank for runtime parameters that the model should fill when using the tool later.",
          items: %{
            type: "object",
            properties: %{
              name: %{type: "string", description: "Parameter name"},
              type: %{
                type: "string",
                description: "Parameter type",
                enum: Tool.param_types()
              },
              value: %{
                type: "string",
                description: "Default value. Leave empty for LLM-provided runtime parameters."
              }
            },
            required: ["name", "type"]
          }
        },
        header_rows: %{
          type: "array",
          description: "Static headers to save with the tool, such as Authorization",
          items: %{
            type: "object",
            properties: %{
              key: %{type: "string", description: "Header name"},
              value: %{type: "string", description: "Header value"}
            },
            required: ["key", "value"]
          }
        }
      },
      required: ["name", "description", "endpoint"]
    }
  end

  @impl true
  def execute(input, context) do
    organization_id = Map.get(context, :organization_id)

    if organization_id do
      App.Agents.Tools.do_create_tool(input, organization_id)
    else
      {:error, "Tool creation requires an active organization"}
    end
  end
end
