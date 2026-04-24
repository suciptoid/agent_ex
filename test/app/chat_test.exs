defmodule App.ChatTest do
  use App.DataCase, async: false

  alias App.Chat
  alias App.Chat.Orchestrator
  alias App.Chat.ContextBuilder

  import App.AgentsFixtures
  import App.ChatFixtures
  import App.ProvidersFixtures
  import App.ToolsFixtures
  import App.UsersFixtures

  setup do
    previous_runner = Application.get_env(:app, :agent_runner)
    Application.put_env(:app, :agent_runner, App.TestSupport.AgentRunnerStub)

    on_exit(fn ->
      if previous_runner do
        Application.put_env(:app, :agent_runner, previous_runner)
      else
        Application.delete_env(:app, :agent_runner)
      end
    end)

    user = user_fixture()
    scope = user_scope_fixture(user)
    provider = provider_fixture(user)
    agent = agent_fixture(user, %{provider: provider, name: "Lead Agent"})

    %{user: user, scope: scope, provider: provider, agent: agent}
  end

  describe "list_chat_rooms/1" do
    test "returns only rooms owned by the current user", %{scope: scope, user: user, agent: agent} do
      room = chat_room_fixture(user, %{title: "Planning", agents: [agent]})

      other_user = user_fixture()
      other_provider = provider_fixture(other_user)
      other_agent = agent_fixture(other_user, %{provider: other_provider})
      _other_room = chat_room_fixture(other_user, %{title: "Other", agents: [other_agent]})

      assert [listed_room] = Chat.list_chat_rooms(scope)
      assert listed_room.id == room.id
      assert Enum.map(listed_room.agents, & &1.id) == [agent.id]
    end
  end

  describe "list_chat_rooms_for_sidebar/1" do
    test "marks rooms with pending assistant replies as loading", %{
      scope: scope,
      user: user,
      agent: agent
    } do
      loading_room = chat_room_fixture(user, %{title: "Loading Room", agents: [agent]})
      idle_room = chat_room_fixture(user, %{title: "Idle Room", agents: [agent]})

      _user_message = message_fixture(loading_room, %{role: "user", content: "Working on it"})

      _pending_assistant =
        message_fixture(loading_room, %{
          role: "assistant",
          content: nil,
          status: :pending,
          agent_id: agent.id
        })

      _completed_assistant =
        message_fixture(idle_room, %{
          role: "assistant",
          content: "Done",
          status: :completed,
          agent_id: agent.id
        })

      sidebar_rooms = Chat.list_chat_rooms_for_sidebar(scope)
      loading_entry = Enum.find(sidebar_rooms, &(&1.id == loading_room.id))
      idle_entry = Enum.find(sidebar_rooms, &(&1.id == idle_room.id))

      assert loading_entry.loading
      refute idle_entry.loading
    end

    test "shows chat and gateway rooms in the sidebar while keeping archived rooms out",
         %{
           scope: scope,
           user: user,
           agent: agent
         } do
      alias App.Gateways

      linked_provider = provider_fixture(user)
      linked_agent = agent_fixture(user, %{provider: linked_provider, name: "Gateway Agent"})

      {:ok, gateway} =
        Gateways.create_gateway(scope, %{
          "name" => "Telegram Bot",
          "type" => "telegram",
          "token" => "telegram-token",
          "config" => %{"agent_id" => linked_agent.id, "allow_all_users" => true}
        })

      {:ok, linked_channel} =
        Gateways.find_or_create_channel(gateway, %{
          external_chat_id: "1234",
          external_user_id: "5678",
          external_username: "Gateway User"
        })

      regular_room = chat_room_fixture(user, %{title: "Regular Room", agents: [agent]})

      archived_room =
        chat_room_fixture(user, %{title: "Archived Room", agents: [agent], type: :archived})

      sidebar_rooms = Chat.list_chat_rooms_for_sidebar(scope)
      management_rooms = Chat.list_chat_room_summaries(scope)
      linked_entry = Enum.find(sidebar_rooms, &(&1.id == linked_channel.chat_room_id))
      regular_entry = Enum.find(sidebar_rooms, &(&1.id == regular_room.id))
      archived_entry = Enum.find(sidebar_rooms, &(&1.id == archived_room.id))
      linked_summary = Enum.find(management_rooms, &(&1.id == linked_channel.chat_room_id))

      assert regular_entry
      assert regular_entry.type == :chat
      assert linked_entry
      assert linked_entry.gateway_linked
      assert archived_entry == nil
      assert linked_summary.gateway_linked
    end
  end

  describe "create_chat_room/2" do
    test "creates a room with selected agents and commander", %{
      scope: scope,
      user: user,
      provider: provider,
      agent: first_agent
    } do
      second_agent = agent_fixture(user, %{provider: provider, name: "Second Agent"})

      assert {:ok, chat_room} =
               Chat.create_chat_room(scope, %{
                 "title" => "Strategy Room",
                 "agent_ids" => [first_agent.id, second_agent.id],
                 "active_agent_id" => second_agent.id
               })

      assert chat_room.title == "Strategy Room"

      assert Enum.sort(Enum.map(chat_room.agents, & &1.id)) ==
               Enum.sort([first_agent.id, second_agent.id])

      commander = Enum.find(chat_room.chat_room_agents, & &1.is_active)
      assert commander.agent_id == second_agent.id
    end

    test "rejects agents owned by another user", %{scope: scope, agent: agent} do
      other_user = user_fixture()
      other_provider = provider_fixture(other_user)
      other_agent = agent_fixture(other_user, %{provider: other_provider})

      assert {:error, changeset} =
               Chat.create_chat_room(scope, %{
                 "title" => "Invalid Room",
                 "agent_ids" => [agent.id, other_agent.id],
                 "active_agent_id" => agent.id
               })

      assert "must belong to the current organization" in errors_on(changeset).agent_ids
    end
  end

  describe "create_message/2" do
    test "moves conflicting explicit positions forward for delegated tool activity", %{
      user: user,
      agent: agent
    } do
      room =
        chat_room_fixture(user, %{
          title: "Delegation",
          agents: [agent],
          active_agent_id: agent.id
        })

      _user_message = message_fixture(room, %{role: "user", content: "Delegate this"})

      parent_message =
        message_fixture(room, %{
          role: "assistant",
          content: nil,
          status: :pending,
          agent_id: agent.id
        })

      assert parent_message.position == 2

      assert {:ok, delegated_placeholder} =
               Chat.create_message(room, %{
                 role: "assistant",
                 content: nil,
                 status: :pending,
                 agent_id: agent.id,
                 metadata: %{"delegated" => true, "tool_name" => "ask_agent"}
               })

      assert delegated_placeholder.position == 3

      assert {:ok, tool_message} =
               Chat.create_message(room, %{
                 role: "tool",
                 content: "Asked the delegated agent to continue.",
                 name: "ask_agent",
                 tool_call_id: "tool_ask_agent",
                 parent_message_id: parent_message.id,
                 position: 3
               })

      assert tool_message.position == 4

      assert {:ok, final_assistant_message} =
               Chat.create_message(room, %{
                 role: "assistant",
                 content: "Delegation complete.",
                 agent_id: agent.id,
                 position: 4
               })

      assert final_assistant_message.position == 5
      assert Enum.map(Chat.list_messages(room), & &1.position) == [1, 2, 3, 4, 5]
    end
  end

  describe "add_agent_to_room/4" do
    test "adds a new commander to an existing room", %{
      scope: scope,
      user: user,
      provider: provider,
      agent: first_agent
    } do
      room =
        chat_room_fixture(user, %{
          title: "Ops",
          agents: [first_agent],
          active_agent_id: first_agent.id
        })

      second_agent = agent_fixture(user, %{provider: provider, name: "Closer"})

      assert {:ok, added_agent} =
               Chat.add_agent_to_room(scope, room, second_agent.id, is_active: true)

      reloaded_room = Chat.get_chat_room!(scope, room.id)
      commander = Enum.find(reloaded_room.chat_room_agents, & &1.is_active)

      assert added_agent.agent_id == second_agent.id
      assert commander.agent_id == second_agent.id
    end
  end

  describe "list_messages/1" do
    test "returns messages ordered by insertion", %{user: user, agent: agent} do
      room = chat_room_fixture(user, %{title: "Thread", agents: [agent]})
      first_message = message_fixture(room, %{role: "user", content: "First"})

      second_message =
        message_fixture(room, %{role: "assistant", content: "Second", agent_id: agent.id})

      assert [listed_first, listed_second] = Chat.list_messages(room)
      assert listed_first.id == first_message.id
      assert listed_second.id == second_message.id
    end
  end

  describe "send_message/3" do
    test "persists the user and assistant messages", %{scope: scope, user: user, agent: agent} do
      room =
        chat_room_fixture(user, %{
          title: "Delivery",
          agents: [agent],
          active_agent_id: agent.id
        })

      assert {:ok, assistant_message} = Chat.send_message(scope, room, "Plan next week")

      messages = Chat.list_messages(room)

      assert Enum.map(messages, & &1.role) == ["user", "assistant"]
      assert Enum.at(messages, 0).content == "Plan next week"
      assert assistant_message.content == "Lead Agent: Plan next week"
      assert assistant_message.agent_id == agent.id
    end

    test "persists tool results as child tool messages", %{scope: scope, user: user, agent: agent} do
      previous_runner = Application.get_env(:app, :agent_runner)
      Application.put_env(:app, :agent_runner, App.TestSupport.StreamingMetadataRunnerStub)

      on_exit(fn ->
        restore_app_env(:agent_runner, previous_runner)
      end)

      room =
        chat_room_fixture(user, %{
          title: "Tool History",
          agents: [agent],
          active_agent_id: agent.id
        })

      assert {:ok, assistant_message} = Chat.send_message(scope, room, "Fetch the data")

      messages = Chat.list_messages(room)

      assert Enum.map(messages, & &1.role) == ["user", "assistant", "tool", "assistant"]
      [user_message, tool_call_message, tool_message, final_assistant_message] = messages

      assert user_message.content == "Fetch the data"
      assert tool_call_message.metadata["thinking"] == "Planning the lookup"
      assert length(tool_call_message.metadata["tool_calls"]) == 1
      assert tool_message.role == "tool"
      assert tool_message.parent_message_id == tool_call_message.id
      assert tool_message.name == "web_fetch"
      assert tool_message.tool_call_id == "tool_1"
      assert tool_message.content == "sample payload"
      assert tool_message.metadata["arguments"] == %{"url" => "https://example.com/data.txt"}
      assert is_nil(tool_message.metadata["thinking"])
      assert assistant_message.id == final_assistant_message.id
      assert final_assistant_message.metadata["thinking"] == "Summarizing the fetched payload"
    end

    test "retries with forced checkpoint compaction after context overflow", %{
      scope: scope,
      user: user,
      provider: provider
    } do
      previous_runner = Application.get_env(:app, :agent_runner)
      previous_compaction = Application.get_env(:app, :chat_compaction)
      previous_builder_config = Application.get_env(:app, ContextBuilder)
      previous_runner_config = Application.get_env(:app, App.TestSupport.OverflowAwareRunnerStub)
      previous_compaction_config = Application.get_env(:app, App.TestSupport.ChatCompactionStub)

      Application.put_env(:app, :agent_runner, App.TestSupport.OverflowAwareRunnerStub)
      Application.put_env(:app, :chat_compaction, App.TestSupport.ChatCompactionStub)

      Application.put_env(:app, ContextBuilder,
        raw_tail_tokens: 1,
        force_raw_tail_tokens: 1,
        checkpoint_source_tokens: 200,
        force_checkpoint_source_tokens: 200
      )

      Application.put_env(:app, App.TestSupport.OverflowAwareRunnerStub, notify_pid: self())
      Application.put_env(:app, App.TestSupport.ChatCompactionStub, notify_pid: self())

      on_exit(fn ->
        restore_app_env(:agent_runner, previous_runner)
        restore_app_env(:chat_compaction, previous_compaction)
        restore_app_env(ContextBuilder, previous_builder_config)
        restore_app_env(App.TestSupport.OverflowAwareRunnerStub, previous_runner_config)
        restore_app_env(App.TestSupport.ChatCompactionStub, previous_compaction_config)
      end)

      agent = agent_fixture(user, %{provider: provider, name: "Lead Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Overflow Room",
          agents: [agent],
          active_agent_id: agent.id
        })

      _old_user =
        message_fixture(room, %{role: "user", content: String.duplicate("Earlier question ", 12)})

      _old_assistant =
        message_fixture(room, %{
          role: "assistant",
          content: String.duplicate("Earlier answer ", 12),
          agent_id: agent.id
        })

      assert {:ok, assistant_message} = Chat.send_message(scope, room, "Need the latest answer")

      assert_receive {:overflow_runner_call, :sync, first_attempt_messages}
      refute Enum.any?(first_attempt_messages, &(&1.role == "checkpoint"))

      assert_receive {:chat_compaction_called, _latest_checkpoint, compaction_messages}
      assert Enum.map(compaction_messages, & &1.role) == ["user", "assistant"]

      assert_receive {:overflow_runner_call, :sync, second_attempt_messages}
      assert Enum.any?(second_attempt_messages, &(&1.role == "checkpoint"))

      persisted_messages = Chat.list_messages(room)
      checkpoint_message = Enum.find(persisted_messages, &(&1.role == "checkpoint"))

      assert assistant_message.content == "Lead Agent: Need the latest answer"
      assert checkpoint_message
      assert checkpoint_message.metadata["up_to_position"] == 2

      assert Enum.map(persisted_messages, & &1.role) == [
               "user",
               "assistant",
               "user",
               "checkpoint",
               "assistant"
             ]
    end

    test "persists a checkpoint even when overflow still cannot be recovered", %{
      scope: scope,
      user: user,
      provider: provider
    } do
      previous_runner = Application.get_env(:app, :agent_runner)
      previous_compaction = Application.get_env(:app, :chat_compaction)
      previous_builder_config = Application.get_env(:app, ContextBuilder)
      previous_runner_config = Application.get_env(:app, App.TestSupport.OverflowAwareRunnerStub)
      previous_compaction_config = Application.get_env(:app, App.TestSupport.ChatCompactionStub)

      Application.put_env(:app, :agent_runner, App.TestSupport.OverflowAwareRunnerStub)
      Application.put_env(:app, :chat_compaction, App.TestSupport.ChatCompactionStub)

      Application.put_env(:app, ContextBuilder,
        raw_tail_tokens: 1,
        force_raw_tail_tokens: 1,
        checkpoint_source_tokens: 200,
        force_checkpoint_source_tokens: 200
      )

      Application.put_env(:app, App.TestSupport.OverflowAwareRunnerStub,
        notify_pid: self(),
        succeed_after_checkpoint: false
      )

      Application.put_env(:app, App.TestSupport.ChatCompactionStub, notify_pid: self())

      on_exit(fn ->
        restore_app_env(:agent_runner, previous_runner)
        restore_app_env(:chat_compaction, previous_compaction)
        restore_app_env(ContextBuilder, previous_builder_config)
        restore_app_env(App.TestSupport.OverflowAwareRunnerStub, previous_runner_config)
        restore_app_env(App.TestSupport.ChatCompactionStub, previous_compaction_config)
      end)

      agent = agent_fixture(user, %{provider: provider, name: "Lead Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Overflow Fallback",
          agents: [agent],
          active_agent_id: agent.id
        })

      _old_user =
        message_fixture(room, %{role: "user", content: String.duplicate("Earlier question ", 12)})

      _old_assistant =
        message_fixture(room, %{
          role: "assistant",
          content: String.duplicate("Earlier answer ", 12),
          agent_id: agent.id
        })

      assert {:error, message} = Chat.send_message(scope, room, "Need the latest answer")
      assert message =~ "Conversation exceeded the model context window"

      persisted_messages = Chat.list_messages(room)
      checkpoint_message = Enum.find(persisted_messages, &(&1.role == "checkpoint"))

      assert checkpoint_message
      assert checkpoint_message.metadata["up_to_position"] == 2
      assert checkpoint_message.content =~ "Checkpoint summary"

      assert Enum.any?(
               persisted_messages,
               &(&1.role == "user" && &1.content == "Need the latest answer")
             )

      assert Enum.map(persisted_messages, & &1.role) == [
               "user",
               "assistant",
               "user",
               "checkpoint"
             ]
    end
  end

  describe "stream_message/3" do
    test "injects subagent tools and agent roster with id, name, and tools in the extra prompt",
         %{
           user: user,
           provider: provider
         } do
      previous_stub_config = Application.get_env(:app, App.TestSupport.AgentRunnerStub)

      Application.put_env(:app, App.TestSupport.AgentRunnerStub, notify_pid: self())

      on_exit(fn ->
        restore_app_env(App.TestSupport.AgentRunnerStub, previous_stub_config)
      end)

      lead_agent = agent_fixture(user, %{provider: provider, name: "Lead Agent"})
      research_agent = agent_fixture(user, %{provider: provider, name: "Research Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Delegation",
          agents: [lead_agent, research_agent],
          active_agent_id: lead_agent.id
        })

      assert {:ok, _user_message} =
               Chat.create_message(room, %{role: "user", content: "Delegate the research task"})

      messages = Chat.list_messages(room)

      assert {:ok, %{content: content, agent_id: agent_id}} =
               Orchestrator.stream_message(room, messages, self())

      assert content == "Lead Agent: Delegate the research task"
      assert agent_id == lead_agent.id

      assert_receive {:agent_runner_streaming_opts, opts}

      extra_tools = opts[:extra_tools] || []
      extra_prompt = opts[:extra_system_prompt] || ""

      assert App.Agents.AlloyTools.SubagentLists in extra_tools
      assert App.Agents.AlloyTools.SubagentSpawn in extra_tools
      assert App.Agents.AlloyTools.SubagentWait in extra_tools
      refute App.Agents.AlloyTools.AskAgent in extra_tools
      refute App.Agents.AlloyTools.Handover in extra_tools

      assert extra_prompt =~ "subagent_lists"
      assert extra_prompt =~ "Before writing a prompt for a sub-agent"
      assert extra_prompt =~ "maximizes that agent's own tool usage"
      assert extra_prompt =~ "wait up to 60 seconds"
      assert extra_prompt =~ "report back later through `subagent_report`"
      assert extra_prompt =~ research_agent.id
      assert extra_prompt =~ research_agent.name
      assert extra_prompt =~ "Available Agents"
    end

    test "subagent_lists returns the other agents with instructions and tool details", %{
      user: user,
      provider: provider
    } do
      custom_tool = tool_fixture(user, %{name: "weather_lookup", description: "Look up weather."})

      lead_agent =
        agent_fixture(user, %{
          provider: provider,
          name: "Lead Agent",
          system_prompt: "Coordinate the overall response.",
          tools: ["web_fetch"]
        })

      research_agent =
        agent_fixture(user, %{
          provider: provider,
          name: "Research Agent",
          system_prompt: "Investigate market data and cite sources.",
          tools: ["web_fetch", custom_tool.name]
        })

      reviewer_agent =
        agent_fixture(user, %{
          provider: provider,
          name: "Reviewer Agent",
          system_prompt: "Review delegated drafts for accuracy.",
          tools: []
        })

      room =
        chat_room_fixture(user, %{
          title: "Delegation Stream",
          agents: [lead_agent, research_agent, reviewer_agent],
          active_agent_id: lead_agent.id
        })

      {:ok, response} =
        App.Agents.AlloyTools.SubagentLists.execute(%{}, %{
          chat_room: room,
          agent_map: %{
            lead_agent.id => lead_agent,
            research_agent.id => research_agent,
            reviewer_agent.id => reviewer_agent
          },
          agents: [lead_agent, research_agent, reviewer_agent],
          current_agent_id: lead_agent.id
        })

      %{"agents" => listed_agents} = Jason.decode!(response)
      listed_ids = Enum.map(listed_agents, &Map.get(&1, "agent_id"))

      refute lead_agent.id in listed_ids
      assert research_agent.id in listed_ids
      assert reviewer_agent.id in listed_ids

      research_entry = Enum.find(listed_agents, &(Map.get(&1, "agent_id") == research_agent.id))
      reviewer_entry = Enum.find(listed_agents, &(Map.get(&1, "agent_id") == reviewer_agent.id))

      assert research_entry["instructions"] == "Investigate market data and cite sources."

      assert research_entry["tools"] == [
               %{
                 "name" => "web_fetch",
                 "description" =>
                   "Fetch the content of a web page given a URL. Optional headers can be included for authenticated requests."
               },
               %{"name" => "weather_lookup", "description" => "Look up weather."}
             ]

      assert reviewer_entry["instructions"] == "Review delegated drafts for accuracy."
      assert reviewer_entry["tools"] == []
    end

    test "spawns a subagent child room and returns the result through subagent_wait only", %{
      user: user,
      scope: scope,
      provider: provider
    } do
      lead_agent = agent_fixture(user, %{provider: provider, name: "Lead Agent"})
      research_agent = agent_fixture(user, %{provider: provider, name: "Research Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Subagent Parent",
          agents: [lead_agent, research_agent],
          active_agent_id: lead_agent.id
        })

      {:ok, spawn_response} =
        App.Agents.AlloyTools.SubagentSpawn.execute(
          %{
            "agent_id" => research_agent.id,
            "prompt" => "Fetch the delegated payload."
          },
          %{chat_room: room, agent_map: %{research_agent.id => research_agent}, callbacks: []}
        )

      %{"subagent_id" => subagent_id, "status" => "running"} = Jason.decode!(spawn_response)

      child_room = Chat.get_chat_room!(scope, subagent_id)
      research_agent_id = research_agent.id

      assert child_room.parent_id == room.id
      assert Enum.map(child_room.chat_room_agents, & &1.agent_id) == [research_agent_id]

      {:ok, wait_response} =
        App.Agents.AlloyTools.SubagentWait.execute(
          %{"subagent_id" => child_room.id, "timeout_seconds" => 1},
          %{chat_room: room}
        )

      assert %{
               "subagent_id" => ^subagent_id,
               "status" => "completed",
               "agent_id" => ^research_agent_id,
               "content" => "Research Agent: Fetch the delegated payload."
             } = Jason.decode!(wait_response)

      refute Enum.any?(Chat.list_messages(room), fn message ->
               message.role == "assistant" and
                 Map.get(message.metadata || %{}, "subagent") == true
             end)
    end

    test "subagent_report posts back to the parent room and restarts the parent agent", %{
      user: user,
      scope: scope,
      provider: provider
    } do
      lead_agent = agent_fixture(user, %{provider: provider, name: "Lead Agent"})
      research_agent = agent_fixture(user, %{provider: provider, name: "Research Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Async Parent",
          agents: [lead_agent, research_agent],
          active_agent_id: lead_agent.id
        })

      Chat.subscribe_chat_room(room)

      assert {:ok, _user_message} =
               Chat.create_message(room, %{role: "user", content: "Need support on this task"})

      {:ok, child_room} = Chat.create_subagent_chat_room(room, research_agent, %{title: nil})
      child_room_id = child_room.id

      {:ok, report_response} =
        App.Agents.AlloyTools.SubagentReport.execute(
          %{"report" => "Finished the async sub-task."},
          %{chat_room: child_room, parent_chat_room: room, current_agent_id: research_agent.id}
        )

      assert %{
               "subagent_id" => ^child_room_id,
               "status" => "reported",
               "resumed_parent" => true
             } = Jason.decode!(report_response)

      assert_receive {:agent_message_created, report_message}
      assert report_message.chat_room_id == room.id
      assert report_message.agent_id == research_agent.id
      assert report_message.content == "Finished the async sub-task."
      assert report_message.metadata["subagent"] == true
      assert report_message.metadata["tool_name"] == "subagent_report"

      assert_receive {:agent_message_created, placeholder_message}
      assert placeholder_message.chat_room_id == room.id
      assert placeholder_message.agent_id == lead_agent.id
      assert placeholder_message.status == :pending

      placeholder_message_id = placeholder_message.id
      assert_receive {:stream_complete, ^placeholder_message_id, _content}, 2_000

      parent_messages = Chat.list_messages(Chat.get_chat_room!(scope, room.id))

      assert Enum.any?(parent_messages, fn message ->
               message.id == report_message.id and
                 message.content == "Finished the async sub-task."
             end)

      assert Enum.any?(parent_messages, fn message ->
               message.id == placeholder_message.id and message.status == :completed and
                 message.agent_id == lead_agent.id
             end)
    end

    test "marks a streaming tool message completed before the final assistant turn", %{
      user: user,
      provider: provider
    } do
      previous_runner = Application.get_env(:app, :agent_runner)
      previous_stub_config = Application.get_env(:app, App.TestSupport.ToolTurnPauseRunnerStub)

      Application.put_env(:app, :agent_runner, App.TestSupport.ToolTurnPauseRunnerStub)

      Application.put_env(:app, App.TestSupport.ToolTurnPauseRunnerStub,
        notify_pid: self(),
        tool_response: %{
          "id" => "tool_without_event_content",
          "name" => "web_fetch",
          "arguments" => %{"url" => "https://example.com"},
          "content" => nil,
          "status" => "ok"
        }
      )

      on_exit(fn ->
        restore_app_env(:agent_runner, previous_runner)
        restore_app_env(App.TestSupport.ToolTurnPauseRunnerStub, previous_stub_config)
      end)

      agent = agent_fixture(user, %{provider: provider, name: "Tool Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Tool Status",
          agents: [agent],
          active_agent_id: agent.id
        })

      assert {:ok, _user_message} =
               Chat.create_message(room, %{role: "user", content: "Fetch it"})

      messages = Chat.list_messages(room)

      assert {:ok, placeholder_message} =
               Chat.create_message(room, %{
                 role: "assistant",
                 content: nil,
                 status: :pending,
                 agent_id: agent.id,
                 metadata: %{}
               })

      assert {:ok, worker_pid} = Chat.start_stream(room, messages, placeholder_message)
      assert_receive {:tool_turn_runner_started, runner_pid}

      pending_tool_message =
        wait_for_persisted_message(worker_pid, room, fn message ->
          if message.role == "tool" and message.tool_call_id == "tool_without_event_content" do
            message
          end
        end)

      assert pending_tool_message.status == :pending

      send(runner_pid, :emit_tool_result)
      assert_receive {:tool_turn_runner_tool_result_emitted, ^runner_pid}

      completed_tool_message =
        wait_for_persisted_message(worker_pid, room, fn message ->
          if message.id == pending_tool_message.id and message.status == :completed do
            message
          end
        end)

      assert completed_tool_message.content == nil

      ref = Process.monitor(runner_pid)
      worker_ref = Process.monitor(worker_pid)
      send(runner_pid, :continue)
      assert_receive {:DOWN, ^ref, :process, ^runner_pid, _reason}
      assert_receive {:DOWN, ^worker_ref, :process, ^worker_pid, :normal}, 2_000
    end

    test "keeps positions unique when next tool turn arrives before prior tool result is handled",
         %{
           user: user,
           provider: provider
         } do
      previous_runner = Application.get_env(:app, :agent_runner)
      Application.put_env(:app, :agent_runner, App.TestSupport.OutOfOrderToolStreamRunnerStub)

      on_exit(fn ->
        restore_app_env(:agent_runner, previous_runner)
      end)

      agent = agent_fixture(user, %{provider: provider, name: "HN Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Tool Race",
          agents: [agent],
          active_agent_id: agent.id
        })

      assert {:ok, _user_message} =
               Chat.create_message(room, %{role: "user", content: "Read top HN stories"})

      messages = Chat.list_messages(room)

      assert {:ok, placeholder_message} =
               Chat.create_message(room, %{
                 role: "assistant",
                 content: nil,
                 status: :pending,
                 agent_id: agent.id,
                 metadata: %{}
               })

      assert {:ok, worker_pid} = Chat.start_stream(room, messages, placeholder_message)
      worker_ref = Process.monitor(worker_pid)

      assert_receive {:DOWN, ^worker_ref, :process, ^worker_pid, :normal}, 2_000

      persisted_messages = Chat.list_messages(room)
      positions = Enum.map(persisted_messages, & &1.position)

      assert positions == Enum.uniq(positions)
      assert positions == [1, 2, 3, 4, 5, 6]

      [_, first_tool_call, first_tool, second_tool_call, second_tool, final_assistant] =
        persisted_messages

      assert first_tool_call.metadata["tool_calls"] |> List.first() |> Map.get("id") ==
               "tool_topstories"

      assert first_tool.parent_message_id == first_tool_call.id
      assert first_tool.tool_call_id == "tool_topstories"

      assert second_tool_call.metadata["tool_calls"] |> List.first() |> Map.get("id") ==
               "tool_story"

      assert second_tool.parent_message_id == second_tool_call.id
      assert second_tool.tool_call_id == "tool_story"
      assert final_assistant.role == "assistant"
      assert final_assistant.status == :completed
      assert final_assistant.position == 6
    end

    test "retries streaming after context overflow by inserting a checkpoint", %{
      user: user,
      provider: provider
    } do
      previous_runner = Application.get_env(:app, :agent_runner)
      previous_compaction = Application.get_env(:app, :chat_compaction)
      previous_builder_config = Application.get_env(:app, ContextBuilder)
      previous_runner_config = Application.get_env(:app, App.TestSupport.OverflowAwareRunnerStub)
      previous_compaction_config = Application.get_env(:app, App.TestSupport.ChatCompactionStub)

      Application.put_env(:app, :agent_runner, App.TestSupport.OverflowAwareRunnerStub)
      Application.put_env(:app, :chat_compaction, App.TestSupport.ChatCompactionStub)

      Application.put_env(:app, ContextBuilder,
        raw_tail_tokens: 1,
        force_raw_tail_tokens: 1,
        checkpoint_source_tokens: 200,
        force_checkpoint_source_tokens: 200
      )

      Application.put_env(:app, App.TestSupport.OverflowAwareRunnerStub, notify_pid: self())
      Application.put_env(:app, App.TestSupport.ChatCompactionStub, notify_pid: self())

      on_exit(fn ->
        restore_app_env(:agent_runner, previous_runner)
        restore_app_env(:chat_compaction, previous_compaction)
        restore_app_env(ContextBuilder, previous_builder_config)
        restore_app_env(App.TestSupport.OverflowAwareRunnerStub, previous_runner_config)
        restore_app_env(App.TestSupport.ChatCompactionStub, previous_compaction_config)
      end)

      agent = agent_fixture(user, %{provider: provider, name: "Lead Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Overflow Stream",
          agents: [agent],
          active_agent_id: agent.id
        })

      _old_user =
        message_fixture(room, %{role: "user", content: String.duplicate("Earlier question ", 12)})

      _old_assistant =
        message_fixture(room, %{
          role: "assistant",
          content: String.duplicate("Earlier answer ", 12),
          agent_id: agent.id
        })

      assert {:ok, _current_user} =
               Chat.create_message(room, %{role: "user", content: "Need a streamed retry"})

      messages = Chat.list_messages(room)

      assert {:ok, %{content: content, agent_id: agent_id}} =
               Orchestrator.stream_message(room, messages, self())

      assert_receive {:overflow_runner_call, :streaming, first_attempt_messages}
      refute Enum.any?(first_attempt_messages, &(&1.role == "checkpoint"))

      assert_receive {:overflow_runner_call, :streaming, second_attempt_messages}
      assert Enum.any?(second_attempt_messages, &(&1.role == "checkpoint"))

      assert_receive {:stream_chunk, _token}
      assert content == "Lead Agent: Need a streamed retry"
      assert agent_id == agent.id
      assert Enum.any?(Chat.list_messages(room), &(&1.role == "checkpoint"))
    end
  end

  defp restore_app_env(key, nil), do: Application.delete_env(:app, key)
  defp restore_app_env(key, value), do: Application.put_env(:app, key, value)

  defp wait_for_persisted_message(worker_pid, room, callback) do
    Enum.reduce_while(1..100, nil, fn _, _acc ->
      _ = :sys.get_state(worker_pid)

      room
      |> Chat.list_messages()
      |> Enum.find_value(callback)
      |> case do
        nil -> {:cont, nil}
        message -> {:halt, message}
      end
    end) || flunk("expected persisted message to reach the desired state")
  end
end
