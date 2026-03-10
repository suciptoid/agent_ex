defmodule App.ChatFixtures do
  alias App.AgentsFixtures
  alias App.Users.Scope

  def chat_room_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      title: "Research Chat"
    })
  end

  def chat_room_fixture(user, attrs \\ %{}) do
    attrs = Map.new(attrs)

    agents =
      Map.get(attrs, :agents) ||
        Map.get(attrs, "agents") ||
        [AgentsFixtures.agent_fixture(user)]

    agent_ids = Enum.map(agents, & &1.id)

    params =
      attrs
      |> Map.delete(:agents)
      |> Map.delete("agents")
      |> chat_room_attrs()
      |> Map.put(:agent_ids, agent_ids)
      |> Map.put(
        :active_agent_id,
        Map.get(attrs, :active_agent_id) || Map.get(attrs, "active_agent_id") ||
          List.first(agent_ids)
      )

    {:ok, chat_room} = App.Chat.create_chat_room(Scope.for_user(user), params)
    chat_room
  end

  def message_fixture(chat_room, attrs \\ %{}) do
    params =
      Enum.into(attrs, %{
        role: "user",
        content: "Hello there"
      })

    {:ok, message} = App.Chat.create_message(chat_room, params)
    message
  end
end
