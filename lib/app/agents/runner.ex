defmodule App.Agents.Runner do
  @moduledoc """
  Executes an agent against a conversation context using Alloy.
  """

  require Logger

  alias App.Agents.Agent
  alias App.Chat.ContextBuilder
  alias App.Chat.Message
  alias App.Providers.AlloyConfig
  alias App.Providers.Provider

  @default_system_prompt "You are a helpful assistant."
  @default_max_turns 25

  def run(agent, messages, opts \\ [])

  def run(%Agent{provider: %Provider{}} = agent, messages, opts) do
    system_prompt = build_system_prompt(agent, opts)
    alloy_messages = build_alloy_messages(messages, opts)
    alloy_tools = resolve_tools(agent, opts)
    provider = build_provider(agent)

    alloy_opts =
      [
        provider: provider,
        tools: alloy_tools,
        system_prompt: system_prompt,
        messages: alloy_messages,
        max_turns: @default_max_turns,
        context: build_alloy_context(agent, opts)
      ]
      |> merge_extra_params(agent)

    Logger.debug(
      "[Runner] Running agent #{agent.name} with model #{agent.model}, #{length(messages)} messages"
    )

    case Alloy.run(alloy_opts) do
      {:ok, %Alloy.Result{} = result} ->
        {:ok, alloy_result_to_runner_result(result)}

      {:error, %Alloy.Result{error: error}} ->
        Logger.error("[Runner] Alloy run failed: #{inspect(error)}")
        {:error, error}
    end
  end

  def run(%Agent{}, _messages, _opts), do: {:error, "agent provider must be preloaded"}

  def run_streaming(agent, messages, recipient, opts \\ [])

  def run_streaming(
        %Agent{provider: %Provider{}} = agent,
        messages,
        recipient,
        opts
      ) do
    system_prompt = build_system_prompt(agent, opts)
    alloy_messages = build_alloy_messages(messages, opts)
    alloy_tools = resolve_tools(agent, opts)
    provider = build_provider(agent)
    callbacks = build_stream_callbacks(recipient, opts)

    on_chunk = fn chunk ->
      callbacks.on_result.(chunk)
    end

    on_event = fn event ->
      handle_alloy_event(event, callbacks)
    end

    alloy_opts =
      [
        provider: provider,
        tools: alloy_tools,
        system_prompt: system_prompt,
        messages: alloy_messages,
        max_turns: @default_max_turns,
        context: build_alloy_context(agent, opts),
        on_event: on_event
      ]
      |> merge_extra_params(agent)

    Logger.debug("[Runner] Streaming agent #{agent.name}, tools: #{inspect(agent.tools)}")

    case Alloy.stream(nil, on_chunk, alloy_opts) do
      {:ok, %Alloy.Result{} = result} ->
        {:ok, alloy_result_to_runner_result(result)}

      {:error, %Alloy.Result{error: error}} ->
        Logger.error("[Runner] Alloy stream failed: #{inspect(error)}")
        {:error, error}
    end
  end

  def run_streaming(%Agent{}, _messages, _recipient, _opts),
    do: {:error, "agent provider must be preloaded"}

  # ── Private ──

  defp build_provider(%Agent{provider: provider, model: model}) do
    AlloyConfig.to_alloy_provider(provider, model)
  end

  defp build_system_prompt(agent, opts) do
    base = if blank?(agent.system_prompt), do: @default_system_prompt, else: agent.system_prompt
    extra = Keyword.get(opts, :extra_system_prompt, "")

    if blank?(extra), do: base, else: base <> "\n\n" <> extra
  end

  defp build_alloy_messages(messages, _opts) do
    messages
    |> ContextBuilder.canonical_messages()
    |> Enum.flat_map(&to_alloy_message/1)
  end

  defp resolve_tools(agent, opts) do
    App.Agents.Tools.resolve(agent.tools, organization_id: agent.organization_id) ++
      Keyword.get(opts, :extra_tools, [])
  end

  defp build_alloy_context(agent, opts) do
    base = %{
      organization_id: agent.organization_id
    }

    case Keyword.get(opts, :alloy_context) do
      nil -> base
      extra when is_map(extra) -> Map.merge(base, extra)
    end
  end

  defp to_alloy_message(%Message{role: "assistant", content: content} = msg) do
    tool_calls = Message.tool_calls(msg) || []

    if tool_calls == [] do
      [Alloy.Message.assistant(content || "")]
    else
      blocks =
        if(blank?(content), do: [], else: [%{type: "text", text: content}]) ++
          Enum.map(tool_calls, fn tc ->
            %{
              type: "tool_use",
              id: tc["id"] || tc[:id] || "",
              name: tc["name"] || tc[:name] || "",
              input: tc["arguments"] || tc[:arguments] || %{}
            }
          end)

      [Alloy.Message.assistant_blocks(blocks)]
    end
  end

  defp to_alloy_message(%Message{role: "tool", content: content} = msg) do
    tool_call_id = msg.tool_call_id || ""

    [Alloy.Message.tool_result_block(tool_call_id, content || "", false)]
    |> then(fn blocks -> [Alloy.Message.tool_results(blocks)] end)
  end

  defp to_alloy_message(%Message{role: "system", content: content}) do
    # System messages are handled via system_prompt in Alloy; skip them in message list
    # But if there's meaningful content, wrap as user context
    if blank?(content), do: [], else: [Alloy.Message.user("[System context] " <> content)]
  end

  defp to_alloy_message(%Message{role: "checkpoint", content: content}) do
    if blank?(content),
      do: [],
      else: [Alloy.Message.user("[Conversation checkpoint] " <> content)]
  end

  defp to_alloy_message(%Message{content: content}) do
    [Alloy.Message.user(content || "")]
  end

  defp to_alloy_message(%{role: role} = msg) do
    content = Map.get(msg, :content) || Map.get(msg, "content") || ""
    tool_calls = Map.get(msg, :tool_calls, Map.get(msg, "tool_calls", []))

    case role do
      "assistant" ->
        if tool_calls == [] do
          [Alloy.Message.assistant(content)]
        else
          blocks =
            if(blank?(content), do: [], else: [%{type: "text", text: content}]) ++
              Enum.map(List.wrap(tool_calls), fn tc ->
                %{
                  type: "tool_use",
                  id: Map.get(tc, "id") || Map.get(tc, :id) || "",
                  name: Map.get(tc, "name") || Map.get(tc, :name) || "",
                  input: Map.get(tc, "arguments") || Map.get(tc, :arguments) || %{}
                }
              end)

          [Alloy.Message.assistant_blocks(blocks)]
        end

      "tool" ->
        tool_call_id = Map.get(msg, :tool_call_id) || Map.get(msg, "tool_call_id") || ""

        [
          Alloy.Message.tool_results([
            Alloy.Message.tool_result_block(tool_call_id, content, false)
          ])
        ]

      "system" ->
        if blank?(content), do: [], else: [Alloy.Message.user("[System context] " <> content)]

      "checkpoint" ->
        if blank?(content),
          do: [],
          else: [Alloy.Message.user("[Conversation checkpoint] " <> content)]

      _ ->
        [Alloy.Message.user(content)]
    end
  end

  defp handle_alloy_event(%{event: :thinking_delta, payload: payload}, callbacks) do
    text = Map.get(payload, :text) || Map.get(payload, "text") || ""
    callbacks.on_thinking.(text)
  end

  defp handle_alloy_event(%{event: :tool_start, payload: payload}, callbacks) do
    tool_result = %{
      "id" => Map.get(payload, :tool_use_id) || Map.get(payload, :id) || "",
      "name" => Map.get(payload, :name) || "",
      "arguments" => Map.get(payload, :input) || %{},
      "content" => nil,
      "status" => "running"
    }

    callbacks.on_tool_start.(tool_result)
  end

  defp handle_alloy_event(%{event: :tool_end, payload: payload}, callbacks) do
    tool_result = %{
      "id" => Map.get(payload, :tool_use_id) || Map.get(payload, :id) || "",
      "name" => Map.get(payload, :name) || "",
      "arguments" => Map.get(payload, :input) || %{},
      "content" => Map.get(payload, :result) || "",
      "status" => tool_end_status(payload)
    }

    callbacks.on_tool_result.(tool_result)
  end

  defp handle_alloy_event(%{event: :tool_calls, payload: payload}, callbacks) do
    tool_calls =
      payload
      |> Map.get(:tool_calls, [])
      |> Enum.map(fn tc ->
        %{
          "id" => Map.get(tc, :id) || "",
          "name" => Map.get(tc, :name) || "",
          "arguments" => Map.get(tc, :input) || %{}
        }
      end)

    tool_call_turn = %{
      "content" => Map.get(payload, :text),
      "thinking" => Map.get(payload, :thinking),
      "tool_calls" => tool_calls
    }

    callbacks.on_tool_calls.(tool_call_turn)
  end

  defp handle_alloy_event(_event, _callbacks), do: :ok

  defp tool_end_status(%{error: error}) when not is_nil(error), do: "error"
  defp tool_end_status(_payload), do: "ok"

  defp alloy_result_to_runner_result(%Alloy.Result{} = result) do
    thinking = extract_thinking(result)

    usage =
      case result.usage do
        %Alloy.Usage{} = u ->
          %{
            "input_tokens" => u.input_tokens,
            "output_tokens" => u.output_tokens,
            "cache_creation_input_tokens" => u.cache_creation_input_tokens,
            "cache_read_input_tokens" => u.cache_read_input_tokens
          }

        _ ->
          nil
      end

    tool_responses = extract_tool_responses(result)
    tool_call_turns = extract_tool_call_turns(result)

    %{
      content: result.text || "",
      thinking: thinking || "",
      tool_responses: tool_responses,
      tool_call_turns: tool_call_turns,
      usage: usage,
      finish_reason: to_string(result.status),
      provider_meta: result.metadata || %{}
    }
  end

  defp extract_thinking(%Alloy.Result{messages: messages}) do
    messages
    |> Enum.flat_map(fn msg ->
      case msg.content do
        blocks when is_list(blocks) ->
          Enum.flat_map(blocks, fn
            %{type: "thinking", text: text} -> [text]
            _ -> []
          end)

        _ ->
          []
      end
    end)
    |> Enum.join("")
  end

  defp extract_tool_responses(%Alloy.Result{tool_calls: tool_calls}) when is_list(tool_calls) do
    Enum.map(tool_calls, fn tc ->
      %{
        "id" => Map.get(tc, :id) || Map.get(tc, "id") || "",
        "name" => Map.get(tc, :name) || Map.get(tc, "name") || "",
        "arguments" => normalize_metadata(Map.get(tc, :input) || Map.get(tc, "input") || %{}),
        "content" => Map.get(tc, :result) || Map.get(tc, "result") || "",
        "status" => "ok"
      }
    end)
  end

  defp extract_tool_responses(_result), do: []

  defp extract_tool_call_turns(%Alloy.Result{messages: messages}) do
    messages
    |> Enum.filter(fn msg -> msg.role == :assistant and has_tool_use?(msg) end)
    |> Enum.map(fn msg ->
      blocks = List.wrap(msg.content)

      text =
        Enum.find_value(blocks, fn
          %{type: "text", text: t} -> t
          _ -> nil
        end)

      thinking =
        Enum.find_value(blocks, fn
          %{type: "thinking", text: t} -> t
          _ -> nil
        end)

      tool_calls =
        Enum.flat_map(blocks, fn
          %{type: "tool_use"} = tc ->
            [
              %{
                "id" => tc.id,
                "name" => tc.name,
                "arguments" => normalize_metadata(tc.input)
              }
            ]

          _ ->
            []
        end)

      %{}
      |> maybe_put("content", text)
      |> maybe_put("thinking", thinking)
      |> Map.put("tool_calls", tool_calls)
    end)
  end

  defp has_tool_use?(%{content: blocks}) when is_list(blocks) do
    Enum.any?(blocks, fn
      %{type: "tool_use"} -> true
      _ -> false
    end)
  end

  defp has_tool_use?(_msg), do: false

  defp merge_extra_params(opts, %Agent{extra_params: extra_params, model: model}) do
    extra = extra_params || %{}

    opts
    |> maybe_put_alloy_opt(:temperature, Map.get(extra, "temperature"))
    |> maybe_put_alloy_opt(:max_tokens, Map.get(extra, "max_tokens"))
    |> maybe_put_reasoning_effort(model, extra)
  end

  defp maybe_put_alloy_opt(opts, _key, nil), do: opts
  defp maybe_put_alloy_opt(opts, key, value), do: Keyword.put(opts, key, value)

  @reasoning_effort_atoms %{
    "none" => :none,
    "minimal" => :minimal,
    "low" => :low,
    "medium" => :medium,
    "high" => :high,
    "xhigh" => :xhigh
  }

  defp maybe_put_reasoning_effort(opts, _model, extra) do
    effort = Map.get(extra, "reasoning_effort") || Map.get(extra, :reasoning_effort)

    case effort do
      effort when effort not in [nil, "", "default"] ->
        case Map.get(@reasoning_effort_atoms, to_string(effort)) do
          nil -> opts
          _effort_atom -> opts
        end

      _ ->
        opts
    end
  end

  defp build_stream_callbacks(recipient, opts) do
    %{
      on_result:
        resolve_callback(
          Keyword.get(opts, :on_result),
          recipient,
          fn token -> {:stream_chunk, token} end
        ),
      on_thinking:
        resolve_callback(
          Keyword.get(opts, :on_thinking),
          recipient,
          fn token -> {:stream_thinking_chunk, token} end
        ),
      on_tool_result:
        resolve_callback(
          Keyword.get(opts, :on_tool_result),
          recipient,
          fn tool_result -> {:stream_tool_result, tool_result} end
        ),
      on_tool_calls:
        resolve_callback(
          Keyword.get(opts, :on_tool_calls),
          recipient,
          fn tool_call_turn -> {:stream_tool_calls, tool_call_turn} end
        ),
      on_tool_start:
        resolve_callback(
          Keyword.get(opts, :on_tool_start),
          recipient,
          fn tool_result -> {:stream_tool_started, tool_result} end
        )
    }
  end

  defp resolve_callback(callback, _recipient, _message_builder) when is_function(callback, 1),
    do: callback

  defp resolve_callback(_callback, recipient, message_builder) when is_pid(recipient) do
    fn payload -> send(recipient, message_builder.(payload)) end
  end

  defp resolve_callback(_callback, _recipient, _message_builder), do: fn _payload -> :ok end

  defp blank?(value), do: value in [nil, ""]

  defp normalize_metadata(nil), do: nil
  defp normalize_metadata(value), do: value |> Jason.encode!() |> Jason.decode!()

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
