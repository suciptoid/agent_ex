defmodule App.TestSupport.ChatCompactionStub do
  def generate_summary(_agent, latest_checkpoint, messages, _opts \\ []) do
    notify(latest_checkpoint, messages)

    summary =
      messages
      |> Enum.map(&(Map.get(&1, :content) || Map.get(&1, "content") || ""))
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" | ")
      |> case do
        "" -> "Checkpoint summary"
        content -> "Checkpoint summary: " <> content
      end

    {:ok, summary}
  end

  defp notify(latest_checkpoint, messages) do
    case Application.get_env(:app, __MODULE__, []) |> Keyword.get(:notify_pid) do
      notify_pid when is_pid(notify_pid) ->
        send(notify_pid, {:chat_compaction_called, latest_checkpoint, messages})

      _other ->
        :ok
    end
  end
end
