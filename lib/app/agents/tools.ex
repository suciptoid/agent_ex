defmodule App.Agents.Tools do
  @moduledoc """
  Registry of builtin agent tools.
  """

  require Logger

  @builtin_tool_names ["web_fetch"]

  def available_tools, do: @builtin_tool_names

  def resolve(tool_names) when is_list(tool_names) do
    tool_names
    |> Enum.uniq()
    |> Enum.flat_map(fn
      "web_fetch" -> [web_fetch_tool()]
      _tool_name -> []
    end)
  end

  @doc """
  Executes a list of tool calls against the resolved tools.

  Returns `{:ok, %{messages: [tool_result_message], results: [tool_result]}}`
  or `{:error, reason}`.
  Each `tool_call` is a map with `:id`, `:name`, and `:arguments` (map).
  """
  def execute_all(tool_calls, tools) when is_list(tool_calls) and is_list(tools) do
    tool_map = Map.new(tools, fn t -> {t.name, t} end)

    results =
      Enum.map(tool_calls, fn %{id: id, name: name, arguments: args} ->
        Logger.debug("[Tools] Executing tool #{name} with args: #{inspect(args)}")

        {status, text} =
          case Map.get(tool_map, name) do
            nil ->
              {"error", "Error: unknown tool '#{name}'"}

            tool ->
              case ReqLLM.Tool.execute(tool, args) do
                {:ok, output} ->
                  text = result_to_text(output)
                  Logger.debug("[Tools] Tool #{name} result: #{String.slice(text, 0, 200)}")
                  {"ok", text}

                {:error, reason} ->
                  error_text = "Error: #{inspect(reason)}"
                  Logger.warning("[Tools] Tool #{name} error: #{error_text}")
                  {"error", error_text}
              end
          end

        normalized_args = normalize_metadata(args)

        %{
          message: ReqLLM.Context.tool_result(id, name, text),
          result: %{
            "id" => id,
            "name" => name,
            "arguments" => normalized_args,
            "content" => text,
            "status" => status
          }
        }
      end)

    {:ok,
     %{
       messages: Enum.map(results, & &1.message),
       results: Enum.map(results, & &1.result)
     }}
  end

  def do_web_fetch(%{url: url}) when is_binary(url) do
    case Req.get(url, req_options()) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body_to_text(body)}

      {:ok, %Req.Response{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  def do_web_fetch(%{"url" => url}) when is_binary(url), do: do_web_fetch(%{url: url})
  def do_web_fetch(_args), do: {:error, "Expected a url argument"}

  defp req_options do
    Application.get_env(:app, __MODULE__, [])
    |> Keyword.get(:req_options, [])
  end

  defp web_fetch_tool do
    ReqLLM.tool(
      name: "web_fetch",
      description:
        "Fetch the content of a web page given a URL and return the response body as text.",
      parameter_schema: [
        url: [type: :string, required: true, doc: "The URL to fetch"]
      ],
      callback: &__MODULE__.do_web_fetch/1
    )
  end

  defp result_to_text(body) when is_binary(body), do: body
  defp result_to_text(body) when is_map(body) or is_list(body), do: Jason.encode!(body)
  defp result_to_text(body), do: inspect(body)

  defp body_to_text(body) when is_binary(body), do: body
  defp body_to_text(body) when is_map(body) or is_list(body), do: Jason.encode!(body)
  defp body_to_text(body), do: inspect(body)

  defp normalize_metadata(nil), do: %{}
  defp normalize_metadata(value), do: value |> Jason.encode!() |> Jason.decode!()
end
