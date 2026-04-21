defmodule App.Agents.Tools do
  @moduledoc """
  Registry and runtime for builtin and user-defined agent tools.

  With the Alloy migration, tools are Alloy.Tool behaviour modules.
  """

  require Logger

  alias App.Agents.AlloyTools
  alias App.Tools, as: ToolsContext
  alias App.Tools.Tool

  @builtin_tool_specs [
    %{
      name: "web_fetch",
      description:
        "Fetch the content of a web page given a URL. Optional headers can be included for authenticated requests.",
      visible_on_tool_list?: true
    },
    %{
      name: "shell",
      description:
        "Execute a shell command on the local system and return the combined stdout and stderr. Use carefully.",
      visible_on_tool_list?: true
    },
    %{
      name: "create_tool",
      description:
        "Create and save a reusable HTTP tool for the current organization using the same fields as the tools UI.",
      visible_on_tool_list?: true
    }
  ]
  @builtin_tool_names Enum.map(@builtin_tool_specs, & &1.name)

  def available_tools, do: @builtin_tool_names

  def listable_builtin_tools do
    Enum.filter(@builtin_tool_specs, & &1.visible_on_tool_list?)
  end

  @doc """
  Resolves tool names to Alloy tool modules.

  Returns a list of items that can be placed in Alloy.run's `:tools` option.
  For builtin tools: Alloy.Tool behaviour modules.
  For custom HTTP tools: runtime-generated Alloy.Tool modules.
  """
  def resolve(tool_names, opts \\ []) when is_list(tool_names) and is_list(opts) do
    organization_id = Keyword.get(opts, :organization_id)

    custom_tools =
      case {organization_id, custom_tool_names(tool_names)} do
        {nil, _names} -> []
        {_organization_id, []} -> []
        {organization_id, names} -> ToolsContext.list_named_tools(organization_id, names)
      end

    custom_tool_map = Map.new(custom_tools, fn tool -> {tool.name, tool} end)

    tool_names
    |> Enum.uniq()
    |> Enum.flat_map(fn tool_name ->
      case tool_name do
        "web_fetch" -> [AlloyTools.WebFetch]
        "shell" -> [AlloyTools.Shell]
        "create_tool" -> [AlloyTools.CreateTool]
        _name -> custom_tool(custom_tool_map[tool_name])
      end
    end)
  end

  # ── Tool execution helpers (kept for the implementations) ──

  def do_web_fetch(%{url: url} = args) when is_binary(url) do
    headers =
      args
      |> Map.get(:headers, %{})
      |> normalize_headers()

    req_opts =
      req_options()
      |> Keyword.update(:headers, headers_list(headers), &(headers_list(headers) ++ &1))

    case Req.get(url, req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body_to_text(body)}

      {:ok, %Req.Response{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  def do_web_fetch(args) when is_map(args) do
    args
    |> stringify_keys()
    |> then(fn normalized ->
      do_web_fetch(%{
        url: Map.get(normalized, "url"),
        headers: Map.get(normalized, "headers", [])
      })
    end)
  end

  def do_web_fetch(_args), do: {:error, "Expected a url argument"}

  def do_shell(%{command: command}) when is_binary(command) do
    run_shell(command)
  end

  def do_shell(%{"command" => command}) when is_binary(command), do: run_shell(command)
  def do_shell(_args), do: {:error, "Expected a command argument"}

  def do_create_tool(args, organization_id) when is_map(args) and is_binary(organization_id) do
    attrs =
      args
      |> stringify_keys()
      |> Map.take(["name", "description", "endpoint", "http_method", "param_rows", "header_rows"])
      |> Map.put_new("http_method", "get")

    case ToolsContext.create_tool_for_organization(organization_id, attrs) do
      {:ok, %Tool{} = tool} ->
        {:ok, created_tool_response(tool)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Tool could not be created: #{format_changeset_errors(changeset)}"}
    end
  end

  def do_create_tool(_args, _organization_id), do: {:error, "Expected tool attributes"}

  def execute_http_tool(%App.Agents.AlloyTools.HttpTool{tool: tool}, args) do
    execute_http_tool(tool, args)
  end

  def execute_http_tool(%Tool{} = tool, args) do
    runtime_params =
      tool
      |> Tool.runtime_param_items()
      |> Enum.reduce(%{}, fn item, acc ->
        name = Map.fetch!(item, "name")
        Map.put(acc, name, fetch_runtime_arg(args, name))
      end)

    fixed_params =
      tool
      |> Tool.static_param_items()
      |> Enum.reduce(%{}, fn item, acc ->
        Map.put(acc, Map.fetch!(item, "name"), Map.get(item, "value"))
      end)

    params = Map.merge(fixed_params, runtime_params)
    consumed_names = Tool.template_placeholders(tool)

    case request_for_tool(tool, params, consumed_names) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body_to_text(body)}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{body_to_text(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  defp run_shell(command) do
    trimmed = String.trim(command)

    cond do
      trimmed == "" ->
        {:error, "Command cannot be blank"}

      unsafe_shell_command?(trimmed) ->
        {:error, "Refusing unsafe shell interpolation patterns"}

      true ->
        case System.cmd("/bin/sh", ["-c", trimmed], stderr_to_stdout: true) do
          {output, 0} -> {:ok, output}
          {output, status} -> {:error, "Command exited with status #{status}: #{output}"}
        end
    end
  end

  defp unsafe_shell_command?(command) do
    String.contains?(command, [
      "${var@P}",
      "${!var}",
      "eval $(",
      "eval${",
      "eval ${"
    ])
  end

  defp req_options do
    Application.get_env(:app, __MODULE__, [])
    |> Keyword.get(:req_options, [])
  end

  defp custom_tool(nil), do: []

  defp custom_tool(%Tool{} = tool) do
    [AlloyTools.HttpTool.from_tool(tool)]
  end

  defp request_for_tool(%Tool{http_method: "post"} = tool, params, consumed_names) do
    {url, remaining_params} = build_request_url(tool.endpoint, params, consumed_names)

    Req.post(
      url,
      Keyword.merge(req_options(),
        headers: headers_list(tool.static_headers),
        json: remaining_params
      )
    )
  end

  defp request_for_tool(%Tool{} = tool, params, consumed_names) do
    {url, remaining_params} = build_request_url(tool.endpoint, params, consumed_names)

    Req.get(
      url,
      Keyword.merge(req_options(),
        headers: headers_list(tool.static_headers),
        params: remaining_params
      )
    )
  end

  defp custom_tool_names(tool_names) do
    Enum.reject(tool_names, &(&1 in @builtin_tool_names))
  end

  defp build_request_url(endpoint_template, params, consumed_names) do
    url =
      Enum.reduce(consumed_names, endpoint_template, fn name, acc ->
        String.replace(acc, "{#{name}}", stringify_template_value(Map.get(params, name)))
      end)

    remaining_params = Map.drop(params, consumed_names)
    {url, remaining_params}
  end

  defp headers_list(nil), do: []

  defp headers_list(headers) when is_map(headers) do
    Enum.map(headers, fn {key, value} -> {key, to_string(value)} end)
  end

  defp headers_list(headers) when is_list(headers) do
    Enum.flat_map(headers, fn
      %{"key" => key, "value" => value} -> [{key, to_string(value)}]
      %{key: key, value: value} -> [{key, to_string(value)}]
      {key, value} -> [{to_string(key), to_string(value)}]
      _other -> []
    end)
  end

  defp normalize_headers(headers) when is_map(headers) do
    Map.new(headers, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp normalize_headers(headers) when is_list(headers) do
    Enum.reduce(headers, %{}, fn
      %{"key" => key, "value" => value}, acc -> Map.put(acc, to_string(key), to_string(value))
      %{key: key, value: value}, acc -> Map.put(acc, to_string(key), to_string(value))
      {key, value}, acc -> Map.put(acc, to_string(key), to_string(value))
      _other, acc -> acc
    end)
  end

  defp normalize_headers(_headers), do: %{}

  defp stringify_template_value(nil), do: ""
  defp stringify_template_value(value) when is_binary(value), do: value
  defp stringify_template_value(value), do: to_string(value)

  defp fetch_runtime_arg(args, name) do
    case Map.fetch(args, name) do
      {:ok, value} -> value
      :error -> Map.get(args, String.to_existing_atom(name))
    end
  rescue
    ArgumentError -> nil
  end

  defp stringify_keys(nil), do: %{}

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp body_to_text(body) when is_binary(body), do: body
  defp body_to_text(body) when is_map(body) or is_list(body), do: Jason.encode!(body)
  defp body_to_text(body), do: inspect(body)

  defp created_tool_response(%Tool{} = tool) do
    %{
      id: tool.id,
      name: tool.name,
      description: tool.description,
      endpoint: tool.endpoint,
      http_method: tool.http_method,
      runtime_parameters: Enum.map(Tool.runtime_param_items(tool), &Map.fetch!(&1, "name")),
      fixed_parameters: Enum.map(Tool.static_param_items(tool), &Map.fetch!(&1, "name")),
      header_names: tool.static_headers |> header_names()
    }
  end

  defp header_names(nil), do: []
  defp header_names(headers) when is_map(headers), do: headers |> Map.keys() |> Enum.sort()

  defp format_changeset_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, messages} ->
      "#{field} #{Enum.join(messages, ", ")}"
    end)
    |> Enum.join("; ")
  end
end
