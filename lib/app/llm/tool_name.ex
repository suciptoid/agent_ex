defmodule App.LLM.ToolName do
  @moduledoc false

  @identifier_pattern ~r/^[A-Za-z_][A-Za-z0-9_]*$/

  def valid?(value) when is_binary(value), do: String.match?(value, @identifier_pattern)
  def valid?(_value), do: false
end
