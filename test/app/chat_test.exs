defmodule App.ChatTest do
  use App.DataCase, async: false

  alias App.Chat
  alias App.Chat.Orchestrator

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
  end

  defp restore_app_env(key, nil), do: Application.delete_env(:app, key)
  defp restore_app_env(key, value), do: Application.put_env(:app, key, value)
end
