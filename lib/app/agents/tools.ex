defmodule App.Agents.Tools do
  @moduledoc """
  Registry of builtin agent tools.
  """

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

  defp body_to_text(body) when is_binary(body), do: body
  defp body_to_text(body) when is_map(body) or is_list(body), do: Jason.encode!(body)
  defp body_to_text(body), do: inspect(body)
end
