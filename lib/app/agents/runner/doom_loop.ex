defmodule App.Agents.Runner.DoomLoop do
  @moduledoc false

  @threshold 3

  def threshold, do: @threshold

  def detect(tool_call_turns, current_tool_calls)
      when is_list(tool_call_turns) and is_list(current_tool_calls) do
    recent_calls =
      tool_call_turns
      |> Enum.flat_map(&turn_tool_calls/1)
      |> Enum.map(&normalize_tool_call/1)
      |> Enum.take(-(@threshold - 1))

    Enum.reduce_while(current_tool_calls, recent_calls, fn tool_call, window ->
      normalized_tool_call = normalize_tool_call(tool_call)
      recent_window = Enum.take(window ++ [normalized_tool_call], -@threshold)

      if repeated_call_window?(recent_window) do
        {:halt, {:doom_loop, normalized_tool_call}}
      else
        {:cont, Enum.take(recent_window, -(@threshold - 1))}
      end
    end)
    |> case do
      {:doom_loop, tool_call} -> {:doom_loop, tool_call}
      _window -> :ok
    end
  end

  defp repeated_call_window?(window) when length(window) != @threshold, do: false
  defp repeated_call_window?([first | rest]), do: Enum.all?(rest, &(&1 == first))
  defp repeated_call_window?([]), do: false

  defp normalize_tool_call(tool_call) do
    %{
      name: tool_call_name(tool_call),
      arguments: normalize_arguments(tool_call_arguments(tool_call))
    }
  end

  defp normalize_arguments(nil), do: %{}
  defp normalize_arguments(arguments), do: arguments |> Jason.encode!() |> Jason.decode!()

  defp turn_tool_calls(%{} = tool_call_turn) do
    tool_call_turn
    |> Map.get("tool_calls", Map.get(tool_call_turn, :tool_calls, []))
    |> List.wrap()
  end

  defp tool_call_name(%{} = tool_call),
    do: Map.get(tool_call, :name) || Map.get(tool_call, "name")

  defp tool_call_arguments(%{} = tool_call),
    do: Map.get(tool_call, :arguments) || Map.get(tool_call, "arguments")
end
