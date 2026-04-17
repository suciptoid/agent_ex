defmodule App.Agents.StreamMiddlewareTest do
  use ExUnit.Case, async: true

  alias Alloy.Agent.{Config, State}
  alias App.Agents.StreamMiddleware

  test "emits the latest assistant tool request as a chat tool-call turn" do
    test_pid = self()

    state = %State{
      config: %Config{
        provider: Alloy.Provider.Test,
        provider_config: %{},
        context: %{
          stream_callbacks: %{
            on_tool_calls: fn tool_call_turn ->
              send(test_pid, {:tool_call_turn, tool_call_turn})
            end
          }
        }
      },
      messages: [
        Alloy.Message.user("Fetch the data"),
        Alloy.Message.assistant_blocks([
          %{type: "thinking", thinking: "Planning"},
          %{type: "text", text: "Let me check."},
          %{
            type: "tool_use",
            id: "tool_1",
            name: "web_fetch",
            input: %{"url" => "https://example.com"}
          }
        ])
      ]
    }

    assert ^state = StreamMiddleware.call(:after_tool_request, state)

    assert_receive {:tool_call_turn,
                    %{
                      "content" => "Let me check.",
                      "thinking" => "Planning",
                      "tool_calls" => [
                        %{
                          "id" => "tool_1",
                          "name" => "web_fetch",
                          "arguments" => %{"url" => "https://example.com"}
                        }
                      ]
                    }}
  end
end
