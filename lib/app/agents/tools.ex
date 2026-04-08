defmodule App.Agents.Tools do
  @moduledoc """
  Registry and runtime for builtin and user-defined agent tools.
  """

  require Logger

  alias App.Tools.Tool

  @builtin_tool_names ["web_fetch", "shell"]
  @supported_param_types %{
    "string" => :string,
    "integer" => :integer,
    "number" => :float,
    "boolean" => :boolean
  }

  def available_tools, do: @builtin_tool_names

  def resolve(tool_names, opts \\ []) when is_list(tool_names) and is_list(opts) do
    organization_id = Keyword.get(opts, :organization_id)

    custom_tools =
      case {organization_id, custom_tool_names(tool_names)} do
        {nil, _names} -> []
        {_organization_id, []} -> []
        {organization_id, names} -> App.Tools.list_named_tools(organization_id, names)
      end

    custom_tool_map = Map.new(custom_tools, fn tool -> {tool.name, tool} end)

    tool_names
    |> Enum.uniq()
    |> Enum.flat_map(fn tool_name ->
      case tool_name do
        "web_fetch" -> [web_fetch_tool()]
        "shell" -> [shell_tool()]
        _name -> custom_tool(custom_tool_map[tool_name])
      end
    end)
  end

  @doc """
  Executes a list of tool calls against the resolved tools.

  Returns `{:ok, %{messages: [tool_result_message], results: [tool_result]}}`
  or `{:error, reason}`.
  Each `tool_call` is a map with `:id`, `:name`, and `:arguments` (map).
  """
  def execute_all(tool_calls, tools, opts \\ [])
      when is_list(tool_calls) and is_list(tools) and is_list(opts) do
    tool_map = Map.new(tools, fn t -> {t.name, t} end)
    on_tool_start = tool_start_callback(opts)

    results =
      Enum.map(tool_calls, fn %{id: id, name: name, arguments: args} ->
        Logger.debug("[Tools] Executing tool #{name} with args: #{inspect(args)}")
        normalized_args = normalize_metadata(args)

        on_tool_start.(%{
          "id" => id,
          "name" => name,
          "arguments" => normalized_args,
          "content" => nil,
          "status" => "running"
        })

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
        headers: Map.get(normalized, "headers", %{})
      })
    end)
  end

  def do_web_fetch(_args), do: {:error, "Expected a url argument"}

  def do_shell(%{command: command}) when is_binary(command) do
    run_shell(command)
  end

  def do_shell(%{"command" => command}) when is_binary(command), do: run_shell(command)
  def do_shell(_args), do: {:error, "Expected a command argument"}

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

  defp tool_start_callback(opts) do
    case Keyword.get(opts, :on_tool_start) do
      callback when is_function(callback, 1) -> callback
      _ -> fn _tool_result -> :ok end
    end
  end

  defp req_options do
    Application.get_env(:app, __MODULE__, [])
    |> Keyword.get(:req_options, [])
  end

  defp web_fetch_tool do
    ReqLLM.tool(
      name: "web_fetch",
      description:
        "Fetch the content of a web page given a URL. Optional headers can be included for authenticated requests.",
      parameter_schema: %{
        "type" => "object",
        "properties" => %{
          "url" => %{"type" => "string", "description" => "The URL to fetch"},
          "headers" => %{
            "type" => "object",
            "description" => "Optional HTTP headers such as Authorization",
            "additionalProperties" => %{"type" => "string"}
          }
        },
        "required" => ["url"]
      },
      callback: &__MODULE__.do_web_fetch/1
    )
  end

  defp shell_tool do
    ReqLLM.tool(
      name: "shell",
      description:
        "Execute a shell command on the local system and return the combined stdout and stderr. Use carefully.",
      parameter_schema: [
        command: [type: :string, required: true, doc: "The shell command to execute"]
      ],
      callback: &__MODULE__.do_shell/1
    )
  end

  defp custom_tool(nil), do: []

  defp custom_tool(%Tool{} = tool) do
    [build_http_tool(tool)]
  end

  defp build_http_tool(%Tool{} = tool) do
    ReqLLM.tool(
      name: tool.name,
      description: tool.description,
      parameter_schema: runtime_parameter_schema(tool),
      callback: fn args -> execute_http_tool(tool, args) end
    )
  end

  defp execute_http_tool(%Tool{} = tool, args) do
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

  defp runtime_parameter_schema(%Tool{} = tool) do
    properties =
      tool
      |> Tool.runtime_param_items()
      |> Enum.reduce(%{}, fn item, acc ->
        Map.put(acc, Map.fetch!(item, "name"), %{
          "type" => json_schema_type(Map.fetch!(item, "type")),
          "description" => "Runtime value for #{Map.fetch!(item, "name")}"
        })
      end)

    required = Enum.map(Tool.runtime_param_items(tool), &Map.fetch!(&1, "name"))

    %{
      "type" => "object",
      "properties" => properties,
      "required" => required
    }
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

  defp normalize_headers(headers) when is_map(headers) do
    Map.new(headers, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp normalize_headers(_headers), do: %{}

  defp json_schema_type(type), do: Map.fetch!(@supported_param_types, type)

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

  defp result_to_text(body) when is_binary(body), do: body
  defp result_to_text(body) when is_map(body) or is_list(body), do: Jason.encode!(body)
  defp result_to_text(body), do: inspect(body)

  defp body_to_text(body) when is_binary(body), do: body
  defp body_to_text(body) when is_map(body) or is_list(body), do: Jason.encode!(body)
  defp body_to_text(body), do: inspect(body)

  defp normalize_metadata(nil), do: %{}
  defp normalize_metadata(value), do: value |> Jason.encode!() |> Jason.decode!()
end
