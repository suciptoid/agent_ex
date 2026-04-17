defmodule App.Agents.AlloyTools.Shell do
  @moduledoc false
  @behaviour Alloy.Tool

  @impl true
  def name, do: "shell"

  @impl true
  def description,
    do:
      "Execute a shell command on the local system and return the combined stdout and stderr. Use carefully."

  @impl true
  def input_schema do
    %{
      type: "object",
      properties: %{
        command: %{type: "string", description: "The shell command to execute"}
      },
      required: ["command"]
    }
  end

  @impl true
  def concurrent?, do: false

  @impl true
  def execute(input, _context) do
    App.Agents.Tools.do_shell(input)
  end
end
