defmodule App.ChatTest do
  use App.DataCase, async: false

  alias App.Chat

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
                 "commander_agent_id" => second_agent.id
               })

      assert chat_room.title == "Strategy Room"

      assert Enum.sort(Enum.map(chat_room.agents, & &1.id)) ==
               Enum.sort([first_agent.id, second_agent.id])

      commander = Enum.find(chat_room.chat_room_agents, & &1.is_commander)
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
                 "commander_agent_id" => agent.id
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
          commander_agent_id: first_agent.id
        })

      second_agent = agent_fixture(user, %{provider: provider, name: "Closer"})

      assert {:ok, added_agent} =
               Chat.add_agent_to_room(scope, room, second_agent.id, is_commander: true)

      reloaded_room = Chat.get_chat_room!(scope, room.id)
      commander = Enum.find(reloaded_room.chat_room_agents, & &1.is_commander)

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
          commander_agent_id: agent.id
        })

      assert {:ok, assistant_message} = Chat.send_message(scope, room, "Plan next week")

      messages = Chat.list_messages(room)

      assert Enum.map(messages, & &1.role) == ["user", "assistant"]
      assert Enum.at(messages, 0).content == "Plan next week"
      assert assistant_message.content == "Lead Agent: Plan next week"
      assert assistant_message.agent_id == agent.id
    end
  end
end
