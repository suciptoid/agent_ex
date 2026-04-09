defmodule App.ChatTest do
  use App.DataCase, async: false

  alias App.Chat
  alias App.Chat.Orchestrator
  alias App.Chat.ContextBuilder

  import App.AgentsFixtures
  import App.ChatFixtures
  import App.ProvidersFixtures
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

    test "marks rooms linked to gateway channels", %{scope: scope, user: user, agent: agent} do
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

      sidebar_rooms = Chat.list_chat_rooms_for_sidebar(scope)
      linked_entry = Enum.find(sidebar_rooms, &(&1.id == linked_channel.chat_room_id))
      regular_entry = Enum.find(sidebar_rooms, &(&1.id == regular_room.id))

      assert linked_entry.gateway_linked
      refute regular_entry.gateway_linked
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

      assert "must belong to the current user" in errors_on(changeset).agent_ids
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
    test "delegates ask_agent asynchronously so the delegated reply finishes later", %{
      user: user,
      provider: provider
    } do
      previous_runner = Application.get_env(:app, :agent_runner)
      previous_test_pid = Application.get_env(:app, :delegating_agent_test_pid)

      Application.put_env(:app, :agent_runner, App.TestSupport.DelegatingAgentRunnerStub)
      Application.put_env(:app, :delegating_agent_test_pid, self())

      on_exit(fn ->
        restore_app_env(:agent_runner, previous_runner)
        restore_app_env(:delegating_agent_test_pid, previous_test_pid)
      end)

      lead_agent = agent_fixture(user, %{provider: provider, name: "Lead Agent"})
      research_agent = agent_fixture(user, %{provider: provider, name: "Research Agent"})
      research_agent_id = research_agent.id

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

      assert content == "I'll ask the delegated agent to handle that."
      assert agent_id == lead_agent.id

      assert_receive {:agent_message_created, placeholder_message}
      placeholder_message_id = placeholder_message.id
      assert placeholder_message.chat_room_id == room.id
      assert placeholder_message.agent_id == research_agent_id
      assert placeholder_message.status == :pending
      assert placeholder_message.content in [nil, ""]

      refute_receive {:agent_message_updated,
                      %{agent_id: ^research_agent_id, status: :completed}},
                     50

      assert_receive {:delegated_agent_started, delegated_pid, ^research_agent_id}
      send(delegated_pid, :continue_delegated_agent)

      assert_receive {:agent_message_stream_chunk, ^placeholder_message_id, _token}
      assert_receive {:agent_message_updated, delegated_message}

      assert delegated_message.id == placeholder_message.id
      assert delegated_message.agent_id == research_agent.id
      assert delegated_message.status == :completed
      assert delegated_message.content == "Research Agent: fetched delegated payload"

      persisted_messages = Chat.list_messages(room)

      assert Enum.map(persisted_messages, & &1.id) == [
               Enum.at(messages, 0).id,
               delegated_message.id
             ]
    end

    test "keeps streaming tool and delegated placeholder positions unique during ask_agent", %{
      user: user,
      provider: provider
    } do
      previous_runner = Application.get_env(:app, :agent_runner)
      Application.put_env(:app, :agent_runner, App.TestSupport.AskAgentStreamingRunnerStub)

      on_exit(fn ->
        restore_app_env(:agent_runner, previous_runner)
      end)

      lead_agent = agent_fixture(user, %{provider: provider, name: "Lead Agent"})
      research_agent = agent_fixture(user, %{provider: provider, name: "Research Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Delegation Stream",
          agents: [lead_agent, research_agent],
          active_agent_id: lead_agent.id
        })

      Chat.subscribe_chat_room(room)

      assert {:ok, _user_message} =
               Chat.create_message(room, %{role: "user", content: "Delegate this task"})

      messages = Chat.list_messages(room)

      assert {:ok, placeholder_message} =
               Chat.create_message(room, %{
                 role: "assistant",
                 content: nil,
                 status: :pending,
                 agent_id: lead_agent.id,
                 metadata: %{}
               })

      assert {:ok, worker_pid} = Chat.start_stream(room, messages, placeholder_message)

      worker_ref = Process.monitor(worker_pid)

      assert_receive {:agent_message_created, delegated_placeholder}
      assert delegated_placeholder.position == 3

      assert_receive {:agent_message_updated, delegated_message}
      assert delegated_message.id == delegated_placeholder.id
      assert delegated_message.status == :completed

      assert_receive {:DOWN, ^worker_ref, :process, ^worker_pid, :normal}

      persisted_messages = Chat.list_messages(room)
      positions = Enum.map(persisted_messages, & &1.position)
      tool_message = Enum.find(persisted_messages, &(&1.role == "tool"))
      final_assistant_message = List.last(persisted_messages)

      assert positions == [1, 2, 3, 4, 5]
      assert placeholder_message.id != final_assistant_message.id
      assert tool_message.position == 4
      assert final_assistant_message.role == "assistant"
      assert final_assistant_message.status == :completed
      assert final_assistant_message.position == 5
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
end
