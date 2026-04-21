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
    {messages_for_provider, provider_opts} = prepare_provider_messages(agent, messages, opts)
    alloy_messages = build_alloy_messages(messages_for_provider, opts)
    alloy_tools = resolve_tools(agent, opts)
    provider = build_provider(agent, provider_opts)
    thinking_enabled? = thinking_enabled?(agent, opts)

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
        {:ok, alloy_result_to_runner_result(result, thinking_enabled?)}

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
    callbacks = build_stream_callbacks(recipient, opts)
    opts = Keyword.put(opts, :stream_callbacks, callbacks)
    {messages_for_provider, provider_opts} = prepare_provider_messages(agent, messages, opts)
    alloy_messages = build_alloy_messages(messages_for_provider, opts)
    alloy_tools = resolve_tools(agent, opts)
    provider = build_provider(agent, provider_opts)
    thinking_enabled? = thinking_enabled?(agent, opts)

    on_chunk = fn chunk ->
      callbacks.on_result.(chunk)
    end

    on_event = fn event ->
      handle_alloy_event(event, callbacks, thinking_enabled?)
    end

    alloy_opts =
      [
        provider: provider,
        tools: alloy_tools,
        system_prompt: system_prompt,
        messages: alloy_messages,
        max_turns: @default_max_turns,
        context: build_alloy_context(agent, opts),
        middleware: stream_middleware(opts),
        on_event: on_event
      ]
      |> merge_extra_params(agent)

    Logger.debug("[Runner] Streaming agent #{agent.name}, tools: #{inspect(agent.tools)}")

    case Alloy.stream(nil, on_chunk, alloy_opts) do
      {:ok, %Alloy.Result{} = result} ->
        {:ok, alloy_result_to_runner_result(result, thinking_enabled?)}

      {:error, %Alloy.Result{error: error}} ->
        Logger.error("[Runner] Alloy stream failed: #{inspect(error)}")
        {:error, error}
    end
  end

  def run_streaming(%Agent{}, _messages, _recipient, _opts),
    do: {:error, "agent provider must be preloaded"}

  # ── Private ──

  defp prepare_provider_messages(%Agent{provider: %Provider{} = provider} = agent, messages, opts) do
    {messages, continuation_opts} = maybe_trim_to_openai_continuation(agent, provider, messages)
    provider_opts = provider_runtime_opts(agent, opts) |> Keyword.merge(continuation_opts)

    {messages, provider_opts}
  end

  defp build_provider(%Agent{provider: provider, model: model}, provider_opts) do
    AlloyConfig.to_alloy_provider(provider, model, provider_opts)
  end

  defp build_system_prompt(agent, opts) do
    base = if blank?(agent.system_prompt), do: @default_system_prompt, else: agent.system_prompt
    extra = Keyword.get(opts, :extra_system_prompt, "")

    if blank?(extra), do: base, else: base <> "\n\n" <> extra
  end

  defp build_alloy_messages(messages, _opts) do
    messages
    |> ContextBuilder.canonical_messages()
    |> Enum.reduce({[], MapSet.new()}, fn message, {alloy_messages, tool_call_ids} ->
      case message_role(message) do
        "assistant" ->
          next_tool_call_ids =
            message
            |> message_tool_calls()
            |> Enum.map(&tool_call_id/1)
            |> Enum.reject(&blank?/1)
            |> Enum.reduce(tool_call_ids, &MapSet.put(&2, &1))

          {alloy_messages ++ to_alloy_message(message), next_tool_call_ids}

        "tool" ->
          if MapSet.member?(tool_call_ids, message_tool_call_id(message)) do
            {alloy_messages ++ to_alloy_message(message), tool_call_ids}
          else
            {alloy_messages ++ orphan_tool_message_to_context(message), tool_call_ids}
          end

        _other ->
          {alloy_messages ++ to_alloy_message(message), tool_call_ids}
      end
    end)
    |> elem(0)
  end

  defp resolve_tools(agent, opts) do
    App.Agents.Tools.resolve(agent.tools, organization_id: agent.organization_id) ++
      Keyword.get(opts, :extra_tools, [])
  end

  defp maybe_trim_to_openai_continuation(%Agent{} = agent, %Provider{} = provider, messages) do
    provider_type = provider.provider_type || provider.provider

    case {latest_provider_response(messages, agent.id), provider_type} do
      {{response_id, index}, "openai"} when is_binary(response_id) ->
        messages_after_response = Enum.drop(messages, index + 1)

        if messages_after_response == [] do
          {messages, []}
        else
          {messages_after_response, [previous_response_id: response_id]}
        end

      _other ->
        {messages, []}
    end
  end

  defp latest_provider_response(messages, agent_id) when is_list(messages) do
    messages
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find_value(fn {message, index} ->
      with true <- same_agent_message?(message, agent_id),
           response_id when is_binary(response_id) <- provider_response_id(message) do
        {response_id, index}
      else
        _other -> nil
      end
    end)
  end

  defp latest_provider_response(_messages, _agent_id), do: nil

  defp same_agent_message?(_message, nil), do: false

  defp same_agent_message?(message, agent_id) do
    case message_agent_id(message) do
      nil -> false
      message_agent_id -> to_string(message_agent_id) == to_string(agent_id)
    end
  end

  defp message_agent_id(%Message{} = message), do: message.agent_id

  defp message_agent_id(%{} = message) do
    Map.get(message, :agent_id) || Map.get(message, "agent_id")
  end

  defp message_agent_id(_message), do: nil

  defp provider_response_id(%Message{} = message),
    do: provider_response_id(message.metadata)

  defp provider_response_id(%{} = metadata) do
    metadata
    |> Map.get(:provider_state, Map.get(metadata, "provider_state"))
    |> case do
      %{"response_id" => response_id} when is_binary(response_id) and response_id != "" ->
        response_id

      %{response_id: response_id} when is_binary(response_id) and response_id != "" ->
        response_id

      _other ->
        nil
    end
  end

  defp provider_response_id(_other), do: nil

  defp provider_runtime_opts(%Agent{} = agent, opts) do
    extra = agent.extra_params || %{}
    provider_type = normalized_provider_type(agent.provider)

    []
    |> maybe_put_provider_opt(
      :max_tokens,
      Map.get(extra, "max_tokens") || Map.get(extra, :max_tokens)
    )
    |> maybe_put_openai_compat_extra(provider_type, "temperature", Map.get(extra, "temperature"))
    |> maybe_put_extended_thinking(provider_type, agent, extra, opts)
  end

  defp maybe_put_provider_opt(opts, _key, nil), do: opts
  defp maybe_put_provider_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp normalized_provider_type(%Provider{provider_type: type})
       when type in ["anthropic", "openai"],
       do: type

  defp normalized_provider_type(%Provider{provider_type: "openai_compat"}), do: "openai_compat"
  defp normalized_provider_type(%Provider{provider: "anthropic"}), do: "anthropic"
  defp normalized_provider_type(%Provider{provider: "openai"}), do: "openai"
  defp normalized_provider_type(%Provider{}), do: "openai_compat"

  defp maybe_put_openai_compat_extra(opts, provider_type, _key, value)
       when provider_type not in ["openai_compat"] or value in [nil, "", "default", :default] do
    opts
  end

  defp maybe_put_openai_compat_extra(opts, _provider_type, key, value) do
    extra_body =
      opts
      |> Keyword.get(:extra_body, %{})
      |> Map.put(key, normalize_provider_param(value))

    Keyword.put(opts, :extra_body, extra_body)
  end

  defp maybe_put_extended_thinking(opts, "anthropic", agent, extra, run_opts) do
    if thinking_enabled?(agent, extra, run_opts) do
      Keyword.put(opts, :extended_thinking,
        budget_tokens: anthropic_thinking_budget(extra, run_opts)
      )
    else
      opts
    end
  end

  defp maybe_put_extended_thinking(opts, _provider_type, _agent, _extra, _run_opts), do: opts

  defp anthropic_thinking_budget(extra, run_opts) do
    extra
    |> Map.get("max_tokens", Map.get(extra, :max_tokens))
    |> case do
      value when is_integer(value) and value >= 1024 -> min(value, 4_096)
      _ -> 2_048
    end
    |> then(&Keyword.get(run_opts, :thinking_budget_tokens, &1))
  end

  defp normalize_provider_param(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_provider_param(value), do: value

  defp message_role(%Message{} = message), do: message.role
  defp message_role(%{} = message), do: Map.get(message, :role) || Map.get(message, "role")
  defp message_role(_message), do: nil

  defp message_tool_calls(%Message{} = message), do: Message.tool_calls(message)

  defp message_tool_calls(%{} = message) do
    message
    |> Map.get(:tool_calls, Map.get(message, "tool_calls", []))
    |> List.wrap()
  end

  defp message_tool_calls(_message), do: []

  defp message_tool_call_id(%Message{} = message), do: message.tool_call_id

  defp message_tool_call_id(%{} = message) do
    Map.get(message, :tool_call_id) || Map.get(message, "tool_call_id")
  end

  defp message_tool_call_id(_message), do: nil

  defp tool_call_id(%{} = tool_call), do: Map.get(tool_call, "id") || Map.get(tool_call, :id)
  defp tool_call_id(_tool_call), do: nil

  defp orphan_tool_message_to_context(message) do
    content =
      [
        "[Tool result from earlier context]",
        "tool: #{message_name(message) || "unknown"}",
        "call_id: #{message_tool_call_id(message) || "unknown"}",
        message_content(message)
      ]
      |> Enum.reject(&blank?/1)
      |> Enum.join("\n")

    [Alloy.Message.user(content)]
  end

  defp message_name(%Message{} = message), do: message.name
  defp message_name(%{} = message), do: Map.get(message, :name) || Map.get(message, "name")
  defp message_name(_message), do: nil

  defp message_content(%Message{} = message), do: message.content

  defp message_content(%{} = message) do
    Map.get(message, :content) || Map.get(message, "content")
  end

  defp message_content(_message), do: nil

  defp build_alloy_context(agent, opts) do
    base =
      %{organization_id: agent.organization_id}
      |> maybe_put(:stream_callbacks, Keyword.get(opts, :stream_callbacks))

    case Keyword.get(opts, :alloy_context) do
      nil -> base
      extra when is_map(extra) -> Map.merge(base, extra)
    end
  end

  defp stream_middleware(opts) do
    [App.Agents.StreamMiddleware | Keyword.get(opts, :middleware, [])]
    |> Enum.uniq()
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

  defp handle_alloy_event(%{event: :thinking_delta, payload: payload}, callbacks, true) do
    callbacks.on_thinking.(thinking_payload_text(payload))
  end

  defp handle_alloy_event(%{event: :thinking_delta}, _callbacks, false), do: :ok

  defp handle_alloy_event(%{event: :tool_start, payload: payload}, callbacks, _thinking_enabled?) do
    tool_result = %{
      "id" => Map.get(payload, :tool_use_id) || Map.get(payload, :id) || "",
      "name" => Map.get(payload, :name) || "",
      "arguments" => Map.get(payload, :input) || %{},
      "content" => nil,
      "status" => "running"
    }

    callbacks.on_tool_start.(tool_result)
  end

  defp handle_alloy_event(%{event: :tool_end, payload: payload}, callbacks, _thinking_enabled?) do
    tool_result = %{
      "id" => Map.get(payload, :tool_use_id) || Map.get(payload, :id) || "",
      "name" => Map.get(payload, :name) || "",
      "arguments" => Map.get(payload, :input) || %{},
      "content" => Map.get(payload, :result) || "",
      "status" => tool_end_status(payload)
    }

    callbacks.on_tool_result.(tool_result)
  end

  defp handle_alloy_event(%{event: :tool_calls, payload: payload}, callbacks, thinking_enabled?) do
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
      "thinking" => if(thinking_enabled?, do: Map.get(payload, :thinking)),
      "tool_calls" => tool_calls
    }

    callbacks.on_tool_calls.(tool_call_turn)
  end

  defp handle_alloy_event(_event, _callbacks, _thinking_enabled?), do: :ok

  defp thinking_payload_text(payload) when is_binary(payload), do: payload

  defp thinking_payload_text(payload) when is_map(payload) do
    Map.get(payload, :text) ||
      Map.get(payload, "text") ||
      Map.get(payload, :thinking) ||
      Map.get(payload, "thinking") ||
      ""
  end

  defp thinking_payload_text(_payload), do: ""

  defp tool_end_status(%{error: error}) when not is_nil(error), do: "error"
  defp tool_end_status(_payload), do: "ok"

  defp alloy_result_to_runner_result(%Alloy.Result{} = result, thinking_enabled?) do
    provider_metadata = result.metadata || %{}

    thinking = if(thinking_enabled?, do: extract_thinking(result))

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
    tool_call_turns = extract_tool_call_turns(result, thinking_enabled?)

    %{
      content: result.text || "",
      thinking: thinking || "",
      tool_responses: tool_responses,
      tool_call_turns: tool_call_turns,
      usage: usage,
      finish_reason: to_string(result.status),
      provider_meta: provider_metadata,
      provider_state: provider_state(provider_metadata)
    }
  end

  defp provider_state(%{} = provider_metadata) do
    Map.get(provider_metadata, :provider_state) || Map.get(provider_metadata, "provider_state") ||
      %{}
  end

  defp provider_state(_provider_metadata), do: %{}

  defp extract_thinking(%Alloy.Result{messages: messages}) do
    messages
    |> Enum.flat_map(fn msg ->
      case msg.content do
        blocks when is_list(blocks) ->
          Enum.flat_map(blocks, fn
            %{type: "thinking", thinking: thinking} -> [thinking]
            %{type: "thinking", text: text} -> [text]
            %{"type" => "thinking", "thinking" => thinking} -> [thinking]
            %{"type" => "thinking", "text" => text} -> [text]
            _ -> []
          end)

        _ ->
          []
      end
    end)
    |> Enum.join("")
  end

  defp extract_tool_responses(%Alloy.Result{messages: messages, tool_calls: tool_calls})
       when is_list(tool_calls) do
    tool_result_content = tool_result_content_by_id(messages)

    Enum.map(tool_calls, fn tc ->
      id = Map.get(tc, :id) || Map.get(tc, "id") || ""

      %{
        "id" => id,
        "name" => Map.get(tc, :name) || Map.get(tc, "name") || "",
        "arguments" => normalize_metadata(Map.get(tc, :input) || Map.get(tc, "input") || %{}),
        "content" =>
          Map.get(tool_result_content, id, Map.get(tc, :result) || Map.get(tc, "result") || ""),
        "status" => if(Map.get(tc, :error) || Map.get(tc, "error"), do: "error", else: "ok")
      }
    end)
  end

  defp extract_tool_responses(_result), do: []

  defp tool_result_content_by_id(messages) when is_list(messages) do
    messages
    |> Enum.flat_map(&tool_result_blocks/1)
    |> Map.new()
  end

  defp tool_result_content_by_id(_messages), do: %{}

  defp tool_result_blocks(%{role: :user, content: blocks}) when is_list(blocks) do
    Enum.flat_map(blocks, &tool_result_block/1)
  end

  defp tool_result_blocks(%{role: "user", content: blocks}) when is_list(blocks) do
    Enum.flat_map(blocks, &tool_result_block/1)
  end

  defp tool_result_blocks(_message), do: []

  defp tool_result_block(%{type: "tool_result", tool_use_id: id, content: content})
       when is_binary(id) and id != "" do
    [{id, content || ""}]
  end

  defp tool_result_block(%{"type" => "tool_result", "tool_use_id" => id, "content" => content})
       when is_binary(id) and id != "" do
    [{id, content || ""}]
  end

  defp tool_result_block(_block), do: []

  defp extract_tool_call_turns(%Alloy.Result{messages: messages}, thinking_enabled?) do
    messages
    |> Enum.filter(fn msg -> msg.role == :assistant and has_tool_use?(msg) end)
    |> Enum.map(fn msg ->
      blocks = List.wrap(msg.content)

      text =
        Enum.find_value(blocks, fn
          %{type: "text", text: t} -> t
          %{"type" => "text", "text" => t} -> t
          _ -> nil
        end)

      thinking =
        if thinking_enabled? do
          Enum.find_value(blocks, fn
            %{type: "thinking", thinking: t} -> t
            %{type: "thinking", text: t} -> t
            %{"type" => "thinking", "thinking" => t} -> t
            %{"type" => "thinking", "text" => t} -> t
            _ -> nil
          end)
        end

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

          %{"type" => "tool_use"} = tc ->
            [
              %{
                "id" => Map.get(tc, "id"),
                "name" => Map.get(tc, "name"),
                "arguments" => normalize_metadata(Map.get(tc, "input") || %{})
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
      %{"type" => "tool_use"} -> true
      _ -> false
    end)
  end

  defp has_tool_use?(_msg), do: false

  defp thinking_enabled?(%Agent{} = agent, opts) do
    thinking_enabled?(agent, agent.extra_params || %{}, opts)
  end

  defp thinking_enabled?(%Agent{}, extra, opts) do
    case thinking_mode(extra, opts) do
      "enabled" -> true
      _ -> false
    end
  end

  defp thinking_mode(extra, opts) do
    Keyword.get(opts, :thinking_mode) ||
      Map.get(extra, "thinking") ||
      Map.get(extra, :thinking) ||
      legacy_thinking_mode(extra)
  end

  defp legacy_thinking_mode(extra) do
    case Map.get(extra, "reasoning_effort") || Map.get(extra, :reasoning_effort) do
      value when value in ["minimal", "low", "medium", "high", "xhigh"] -> "enabled"
      _ -> "disabled"
    end
  end

  defp merge_extra_params(opts, %Agent{}), do: opts

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
