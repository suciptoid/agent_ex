defmodule App.Agents.StreamMiddleware do
  @moduledoc """
  Bridges Alloy tool request hooks back to the chat stream callbacks.
  """

  @behaviour Alloy.Middleware

  alias Alloy.Agent.State
  alias Alloy.Message

  @impl true
  def call(:after_tool_request, %State{} = state) do
    callbacks = Map.get(state.config.context, :stream_callbacks)

    with %{on_tool_calls: on_tool_calls} when is_function(on_tool_calls, 1) <- callbacks,
         %Message{} = message <- latest_tool_request_message(state),
         tool_call_turn when tool_call_turn != nil <- tool_call_turn(message) do
      on_tool_calls.(tool_call_turn)
    end

    state
  end

  def call(_hook, %State{} = state), do: state

  defp latest_tool_request_message(%State{} = state) do
    state
    |> State.messages()
    |> Enum.reverse()
    |> Enum.find(&tool_request_message?/1)
  end

  defp tool_request_message?(%Message{role: :assistant} = message) do
    Message.tool_calls(message) != []
  end

  defp tool_request_message?(_message), do: false

  defp tool_call_turn(%Message{content: blocks}) when is_list(blocks) do
    tool_calls =
      blocks
      |> Enum.filter(&tool_use_block?/1)
      |> Enum.map(fn block ->
        %{
          "id" => Map.get(block, :id) || Map.get(block, "id"),
          "name" => Map.get(block, :name) || Map.get(block, "name"),
          "arguments" => Map.get(block, :input) || Map.get(block, "input") || %{}
        }
      end)

    if tool_calls == [] do
      nil
    else
      %{}
      |> maybe_put("content", first_block_text(blocks))
      |> maybe_put("thinking", first_block_thinking(blocks))
      |> Map.put("tool_calls", tool_calls)
    end
  end

  defp tool_call_turn(_message), do: nil

  defp tool_use_block?(%{type: type}) when type in ["tool_use", "server_tool_use"], do: true
  defp tool_use_block?(%{"type" => type}) when type in ["tool_use", "server_tool_use"], do: true
  defp tool_use_block?(_block), do: false

  defp first_block_text(blocks) do
    Enum.find_value(blocks, fn
      %{type: "text", text: text} when is_binary(text) -> text
      %{"type" => "text", "text" => text} when is_binary(text) -> text
      _block -> nil
    end)
  end

  defp first_block_thinking(blocks) do
    Enum.find_value(blocks, fn
      %{type: "thinking", thinking: thinking} when is_binary(thinking) -> thinking
      %{type: "thinking", text: text} when is_binary(text) -> text
      %{"type" => "thinking", "thinking" => thinking} when is_binary(thinking) -> thinking
      %{"type" => "thinking", "text" => text} when is_binary(text) -> text
      _block -> nil
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
