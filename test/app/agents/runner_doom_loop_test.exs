defmodule App.Agents.Runner.DoomLoopTest do
  use ExUnit.Case, async: true

  alias App.Agents.Runner.DoomLoop

  test "detect/2 flags the third identical tool call in a row" do
    previous_turns = [
      %{"tool_calls" => [%{"name" => "shell", "arguments" => %{"command" => "pwd"}}]},
      %{"tool_calls" => [%{"name" => "shell", "arguments" => %{"command" => "pwd"}}]}
    ]

    assert {:doom_loop, %{name: "shell", arguments: %{"command" => "pwd"}}} =
             DoomLoop.detect(previous_turns, [%{name: "shell", arguments: %{command: "pwd"}}])
  end

  test "detect/2 ignores repeated tools when the input changes" do
    previous_turns = [
      %{"tool_calls" => [%{"name" => "shell", "arguments" => %{"command" => "pwd"}}]},
      %{"tool_calls" => [%{"name" => "shell", "arguments" => %{"command" => "ls"}}]}
    ]

    assert :ok =
             DoomLoop.detect(previous_turns, [%{name: "shell", arguments: %{command: "pwd"}}])
  end

  test "detect/2 tracks repeated tool calls within the current response" do
    previous_turns = [
      %{
        "tool_calls" => [
          %{"name" => "web_fetch", "arguments" => %{"url" => "https://example.test"}}
        ]
      }
    ]

    assert {:doom_loop, %{name: "web_fetch", arguments: %{"url" => "https://example.test"}}} =
             DoomLoop.detect(previous_turns, [
               %{name: "web_fetch", arguments: %{url: "https://example.test"}},
               %{name: "web_fetch", arguments: %{"url" => "https://example.test"}}
             ])
  end
end
