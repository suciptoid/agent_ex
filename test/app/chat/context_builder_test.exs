defmodule App.Chat.ContextBuilderTest do
  use App.DataCase, async: true

  alias App.Chat
  alias App.Chat.ContextBuilder

  import App.AgentsFixtures
  import App.ChatFixtures
  import App.ProvidersFixtures
  import App.UsersFixtures

  setup do
    user = user_fixture()
    provider = provider_fixture(user)
    agent = agent_fixture(user, %{provider: provider, name: "Builder Agent"})
    room = chat_room_fixture(user, %{agents: [agent], active_agent_id: agent.id})

    %{user: user, provider: provider, agent: agent, room: room}
  end

  describe "canonical_messages/1" do
    test "keeps explicit persisted tool transcript without duplication", %{
      agent: agent,
      room: room
    } do
      user_message = message_fixture(room, %{role: "user", content: "Fetch the data"})

      tool_call_message =
        message_fixture(room, %{
          role: "assistant",
          content: "Let me check.",
          agent_id: agent.id,
          metadata: %{
            "tool_calls" => [
              %{
                "id" => "tool_1",
                "name" => "web_fetch",
                "arguments" => %{"url" => "https://example.com/data.txt"}
              }
            ]
          }
        })

      tool_message =
        message_fixture(room, %{
          role: "tool",
          content: "sample payload",
          name: "web_fetch",
          tool_call_id: "tool_1",
          parent_message_id: tool_call_message.id
        })

      final_assistant =
        message_fixture(room, %{
          role: "assistant",
          content: "Here is the answer.",
          agent_id: agent.id
        })

      canonical_messages = room |> Chat.list_messages() |> ContextBuilder.canonical_messages()

      assert Enum.map(canonical_messages, & &1.role) == ["user", "assistant", "tool", "assistant"]
      assert Enum.at(canonical_messages, 0).id == user_message.id
      assert Enum.at(canonical_messages, 1).id == tool_call_message.id
      assert Enum.at(canonical_messages, 2).tool_call_id == tool_message.tool_call_id
      assert Enum.at(canonical_messages, 3).id == final_assistant.id
    end

    test "expands legacy assistant metadata into assistant/tool/final sequence", %{
      agent: agent,
      room: room
    } do
      _user_message = message_fixture(room, %{role: "user", content: "Legacy history"})

      _legacy_assistant =
        message_fixture(room, %{
          role: "assistant",
          content: "Legacy final answer",
          agent_id: agent.id,
          metadata: %{
            "tool_call_turns" => [
              %{
                "content" => "Looking up details",
                "tool_calls" => [
                  %{
                    "id" => "tool_legacy",
                    "name" => "web_fetch",
                    "arguments" => %{"url" => "https://example.com/legacy"}
                  }
                ]
              }
            ],
            "tool_responses" => [
              %{
                "id" => "tool_legacy",
                "name" => "web_fetch",
                "arguments" => %{"url" => "https://example.com/legacy"},
                "content" => "legacy payload",
                "status" => "ok"
              }
            ]
          }
        })

      canonical_messages = room |> Chat.list_messages() |> ContextBuilder.canonical_messages()

      assert Enum.map(canonical_messages, & &1.role) == ["user", "assistant", "tool", "assistant"]
      assert Enum.at(canonical_messages, 1).content == "Looking up details"
      assert Enum.at(canonical_messages, 2).content == "legacy payload"
      assert Enum.at(canonical_messages, 3).content == "Legacy final answer"
    end

    test "removes internal title tool calls from prompt history while preserving visible tools",
         %{
           agent: agent,
           room: room
         } do
      _user_message = message_fixture(room, %{role: "user", content: "Fetch the data"})

      tool_call_message =
        message_fixture(room, %{
          role: "assistant",
          content: "Let me check.",
          agent_id: agent.id,
          metadata: %{
            "tool_calls" => [
              %{
                "id" => "tool_title",
                "name" => "update_chatroom_title",
                "arguments" => %{"title" => "Data request"}
              },
              %{
                "id" => "tool_fetch",
                "name" => "web_fetch",
                "arguments" => %{"url" => "https://example.com/data.txt"}
              }
            ]
          }
        })

      _title_tool_message =
        message_fixture(room, %{
          role: "tool",
          content: "Title set to: Data request",
          name: "update_chatroom_title",
          tool_call_id: "tool_title",
          parent_message_id: tool_call_message.id
        })

      _fetch_tool_message =
        message_fixture(room, %{
          role: "tool",
          content: "sample payload",
          name: "web_fetch",
          tool_call_id: "tool_fetch",
          parent_message_id: tool_call_message.id
        })

      canonical_messages = room |> Chat.list_messages() |> ContextBuilder.canonical_messages()

      assert Enum.map(canonical_messages, & &1.role) == ["user", "assistant", "tool"]
      assistant_message = Enum.at(canonical_messages, 1)
      assert [%{"name" => "web_fetch", "id" => "tool_fetch"}] = assistant_message.tool_calls
      assert Enum.at(canonical_messages, 2).tool_call_id == "tool_fetch"
    end

    test "removes title-only tool turns from prompt history", %{agent: agent, room: room} do
      _user_message = message_fixture(room, %{role: "user", content: "Plan a launch"})

      title_call_message =
        message_fixture(room, %{
          role: "assistant",
          content: nil,
          agent_id: agent.id,
          metadata: %{
            "tool_calls" => [
              %{
                "id" => "tool_title_only",
                "name" => "update_chatroom_title",
                "arguments" => %{"title" => "Launch plan"}
              }
            ]
          }
        })

      _title_tool_message =
        message_fixture(room, %{
          role: "tool",
          content: "Title set to: Launch plan",
          name: "update_chatroom_title",
          tool_call_id: "tool_title_only",
          parent_message_id: title_call_message.id
        })

      _final_assistant =
        message_fixture(room, %{
          role: "assistant",
          content: "Here is the plan.",
          agent_id: agent.id
        })

      canonical_messages = room |> Chat.list_messages() |> ContextBuilder.canonical_messages()

      assert Enum.map(canonical_messages, & &1.role) == ["user", "assistant"]
      assert Enum.at(canonical_messages, 1).content == "Here is the plan."
    end
  end

  describe "budget_policy/2" do
    test "prefers explicit app config over built-in model defaults", %{agent: agent} do
      previous_config = Application.get_env(:app, ContextBuilder)

      Application.put_env(:app, ContextBuilder,
        raw_tail_tokens: 123,
        force_raw_tail_tokens: 45
      )

      on_exit(fn -> restore_app_env(ContextBuilder, previous_config) end)

      policy = ContextBuilder.budget_policy(agent.model)

      assert policy.raw_tail_tokens == 123
      assert policy.force_raw_tail_tokens == 45
    end
  end

  defp restore_app_env(key, nil), do: Application.delete_env(:app, key)
  defp restore_app_env(key, value), do: Application.put_env(:app, key, value)
end
