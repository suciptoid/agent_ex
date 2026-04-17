defmodule App.Agents.AlloyTools.WebFetch do
  @moduledoc false
  @behaviour Alloy.Tool

  @impl true
  def name, do: "web_fetch"

  @impl true
  def description,
    do:
      "Fetch the content of a web page given a URL. Optional headers can be included for authenticated requests."

  @impl true
  def input_schema do
    %{
      type: "object",
      properties: %{
        url: %{type: "string", description: "The URL to fetch"},
        headers: %{
          type: "object",
          description: "Optional HTTP headers such as Authorization",
          additionalProperties: %{type: "string"}
        }
      },
      required: ["url"]
    }
  end

  @impl true
  def execute(input, _context) do
    App.Agents.Tools.do_web_fetch(input)
  end
end
