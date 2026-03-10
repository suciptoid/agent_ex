defmodule App.Chat.Orchestrator do
  @moduledoc """
  Handles message orchestration for chat rooms.
  """

  alias App.Chat
  alias App.Chat.{ChatRoom, ChatRoomAgent}

  def send_message(_scope, %ChatRoom{} = chat_room, content) when is_binary(content) do
    content = String.trim(content)

    if content == "" do
      {:error, "Message cannot be blank"}
    else
      with {:ok, _user_message} <-
             Chat.create_message(chat_room, %{role: "user", content: content}),
           messages <- Chat.list_messages(chat_room),
           {:ok, agent} <- commander_agent(chat_room),
           {:ok, response} <- agent_runner().run(agent, messages),
           assistant_content <-
             ReqLLM.Response.text(response) || "The agent returned an empty response.",
           {:ok, assistant_message} <-
             Chat.create_message(chat_room, %{
               role: "assistant",
               content: assistant_content,
               agent_id: agent.id,
               metadata: response_metadata(response)
             }) do
        {:ok, assistant_message}
      end
    end
  end

  defp commander_agent(%ChatRoom{chat_room_agents: chat_room_agents}) do
    case Enum.find(chat_room_agents, & &1.is_commander) || List.first(chat_room_agents) do
      %ChatRoomAgent{agent: agent} -> {:ok, agent}
      nil -> {:error, "This chat room has no agents assigned"}
    end
  end

  defp response_metadata(response) do
    %{
      "usage" => normalize_metadata(ReqLLM.Response.usage(response)),
      "finish_reason" => response.finish_reason && to_string(response.finish_reason),
      "provider_meta" => normalize_metadata(response.provider_meta)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == %{} end)
    |> Map.new()
  end

  defp normalize_metadata(nil), do: nil
  defp normalize_metadata(value), do: value |> Jason.encode!() |> Jason.decode!()

  defp agent_runner, do: Application.get_env(:app, :agent_runner, App.Agents.Runner)
end
