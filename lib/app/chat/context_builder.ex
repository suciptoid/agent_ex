defmodule App.Chat.ContextBuilder do
  @moduledoc false

  require Logger

  alias App.Agents.Agent
  alias App.Chat
  alias App.Chat.{ChatRoom, Message}

  @checkpoint_version 1
  @old_tool_placeholder "[Older tool result omitted from prompt; stored in transcript]"
  @default_policy %{
    context_window_tokens: 131_072,
    reserve_tokens: 16_384,
    raw_tail_tokens: 24_000,
    force_raw_tail_tokens: 12_000,
    checkpoint_source_tokens: 24_000,
    force_checkpoint_source_tokens: 32_000,
    checkpoint_summary_max_tokens: 1_200,
    compaction_message_chars: 4_000,
    compaction_tool_chars: 600,
    tool_preview_chars: 1_200,
    force_tool_preview_chars: 200,
    max_checkpoint_iterations: 2,
    force_checkpoint_iterations: 3
  }

  @type prompt_message :: %{
          optional(:id) => term(),
          optional(:name) => String.t() | nil,
          optional(:tool_call_id) => String.t() | nil,
          optional(:tool_calls) => list(),
          optional(:metadata) => map(),
          optional(:position) => integer() | nil,
          required(:role) => String.t(),
          required(:content) => String.t() | nil
        }

  def prepare(%ChatRoom{} = chat_room, %Agent{} = agent, messages, opts \\ [])
      when is_list(messages) and is_list(opts) do
    policy = budget_policy(agent.model, opts)
    extra_system_prompt = Keyword.get(opts, :extra_system_prompt, "")
    force_compaction? = Keyword.get(opts, :force_compaction, false)
    canonical_messages = canonical_messages(messages)

    {checkpoint, canonical_messages} =
      maybe_append_checkpoint(chat_room, agent, canonical_messages, policy,
        extra_system_prompt: extra_system_prompt,
        force_compaction: force_compaction?
      )

    prepared_messages =
      canonical_messages
      |> prompt_messages(checkpoint)
      |> maybe_prune_tool_outputs(policy,
        extra_system_prompt: extra_system_prompt,
        force_compaction: force_compaction?
      )

    estimated_tokens =
      estimate_messages_tokens(prepared_messages, extra_system_prompt: extra_system_prompt)

    {:ok,
     %{
       messages: prepared_messages,
       estimated_tokens: estimated_tokens,
       checkpoint: checkpoint,
       policy: policy
     }}
  end

  def canonical_messages(messages) when is_list(messages) do
    explicit_tool_call_ids =
      messages
      |> Enum.filter(&(message_role(&1) == "tool"))
      |> Enum.map(&message_tool_call_id/1)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    Enum.flat_map(messages, &canonical_message(&1, explicit_tool_call_ids))
  end

  def estimate_messages_tokens(messages, opts \\ []) when is_list(messages) and is_list(opts) do
    extra_system_prompt = Keyword.get(opts, :extra_system_prompt, "")

    base_tokens =
      case String.trim(extra_system_prompt) do
        "" -> 0
        prompt -> estimate_text_tokens(prompt)
      end

    Enum.reduce(messages, base_tokens, fn message, acc ->
      acc + estimate_message_tokens(message)
    end)
  end

  def budget_policy(model, opts \\ []) when is_list(opts) do
    config = Application.get_env(:app, __MODULE__, [])

    configured_defaults =
      config
      |> Keyword.drop([:model_overrides])
      |> Enum.into(%{})

    configured_overrides =
      config
      |> Keyword.get(:model_overrides, %{})
      |> resolve_model_overrides(model)

    runtime_overrides =
      opts
      |> Keyword.get(:budget_overrides, %{})
      |> Map.new()

    @default_policy
    |> Map.merge(built_in_model_overrides(model))
    |> Map.merge(configured_defaults)
    |> Map.merge(configured_overrides)
    |> Map.merge(runtime_overrides)
  end

  defp canonical_message(%Message{role: "assistant"} = message, explicit_tool_call_ids) do
    if legacy_compound_assistant?(message, explicit_tool_call_ids) do
      expand_legacy_assistant_message(message)
    else
      [normalize_prompt_message(message)]
    end
  end

  defp canonical_message(message, _explicit_tool_call_ids),
    do: [normalize_prompt_message(message)]

  defp legacy_compound_assistant?(%Message{} = message, explicit_tool_call_ids) do
    tool_call_ids =
      message
      |> Message.tool_call_ids()
      |> Enum.reject(&is_nil/1)

    Message.tool_calls(message) == [] and
      tool_call_ids != [] and
      Enum.all?(tool_call_ids, &(not MapSet.member?(explicit_tool_call_ids, &1)))
  end

  defp expand_legacy_assistant_message(%Message{} = message) do
    tool_responses = Message.tool_responses(message)
    tool_responses_by_call_id = Enum.group_by(tool_responses, &Map.get(&1, "id"))

    {expanded_turns, used_tool_call_ids} =
      Enum.map_reduce(Message.tool_call_turns(message), MapSet.new(), fn tool_call_turn,
                                                                         used_ids ->
        tool_calls = turn_tool_calls(tool_call_turn)

        related_tool_messages =
          tool_calls
          |> Enum.flat_map(fn tool_call ->
            Map.get(tool_responses_by_call_id, tool_call_id(tool_call), [])
          end)
          |> Enum.map(&build_virtual_tool_message(&1, message))

        next_used_ids =
          Enum.reduce(related_tool_messages, used_ids, fn tool_message, acc ->
            case Map.get(tool_message, :tool_call_id) do
              nil -> acc
              tool_call_id -> MapSet.put(acc, tool_call_id)
            end
          end)

        synthetic_turn = build_virtual_tool_call_turn_message(tool_call_turn, message)
        {[synthetic_turn | related_tool_messages], next_used_ids}
      end)

    extra_tool_messages =
      tool_responses
      |> Enum.reject(fn tool_response ->
        MapSet.member?(used_tool_call_ids, Map.get(tool_response, "id"))
      end)
      |> Enum.map(&build_virtual_tool_message(&1, message))

    List.flatten(expanded_turns) ++ extra_tool_messages ++ [normalize_prompt_message(message)]
  end

  defp maybe_append_checkpoint(
         %ChatRoom{} = chat_room,
         %Agent{} = agent,
         canonical_messages,
         policy,
         opts
       ) do
    extra_system_prompt = Keyword.get(opts, :extra_system_prompt, "")
    force_compaction? = Keyword.get(opts, :force_compaction, false)
    max_iterations = checkpoint_iterations(policy, force_compaction?)

    Enum.reduce_while(
      1..max_iterations,
      latest_checkpoint_state(canonical_messages),
      fn _iteration, {checkpoint, messages} ->
        estimated_tokens =
          messages
          |> prompt_messages(checkpoint)
          |> estimate_messages_tokens(extra_system_prompt: extra_system_prompt)

        cond do
          not force_compaction? and estimated_tokens <= threshold_tokens(policy) ->
            {:halt, {checkpoint, messages}}

          true ->
            case create_next_checkpoint(
                   chat_room,
                   agent,
                   messages,
                   checkpoint,
                   policy,
                   estimated_tokens,
                   force_compaction?
                 ) do
              {:ok, nil} ->
                {:halt, {checkpoint, messages}}

              {:ok, checkpoint_message} ->
                normalized_checkpoint = normalize_prompt_message(checkpoint_message)
                {:cont, {normalized_checkpoint, messages ++ [normalized_checkpoint]}}

              {:error, reason} ->
                Logger.warning(
                  "[ContextBuilder] Checkpoint compaction failed: #{inspect(reason)}"
                )

                {:halt, {checkpoint, messages}}
            end
        end
      end
    )
  end

  defp latest_checkpoint_state(canonical_messages) do
    {latest_checkpoint(canonical_messages), canonical_messages}
  end

  defp create_next_checkpoint(
         %ChatRoom{} = chat_room,
         %Agent{} = agent,
         canonical_messages,
         checkpoint,
         policy,
         estimated_tokens,
         force_compaction?
       ) do
    messages_after_checkpoint = uncovered_messages(canonical_messages, checkpoint)
    raw_tail_tokens = raw_tail_tokens(policy, force_compaction?)
    protected_start_index = protected_start_index(messages_after_checkpoint, raw_tail_tokens)

    checkpoint_candidates =
      messages_after_checkpoint
      |> Enum.take(protected_start_index)
      |> fallback_checkpoint_candidates(messages_after_checkpoint, force_compaction?)

    checkpoint_chunk =
      checkpoint_candidates
      |> take_from_start_by_tokens(checkpoint_source_tokens(policy, force_compaction?))

    case List.last(checkpoint_chunk) do
      nil ->
        {:ok, nil}

      last_message ->
        up_to_position = message_position(last_message)

        cond do
          is_nil(up_to_position) ->
            {:ok, nil}

          is_integer(checkpoint_up_to_position(checkpoint)) and
              up_to_position <= checkpoint_up_to_position(checkpoint) ->
            {:ok, nil}

          true ->
            raw_tail_start_position =
              messages_after_checkpoint
              |> Enum.drop(length(checkpoint_chunk))
              |> Enum.find_value(&message_position/1)

            with {:ok, summary} <-
                   compaction_module().generate_summary(agent, checkpoint, checkpoint_chunk,
                     policy: policy
                   ),
                 {:ok, checkpoint_message} <-
                   Chat.create_message(chat_room, %{
                     role: "checkpoint",
                     content: summary,
                     agent_id: agent.id,
                     metadata: %{
                       "up_to_position" => up_to_position,
                       "raw_tail_start_position" => raw_tail_start_position,
                       "estimated_tokens_before" => estimated_tokens,
                       "estimated_tokens_after" => estimate_text_tokens(summary),
                       "checkpoint_version" => @checkpoint_version
                     }
                   }) do
              Logger.info(
                "[ContextBuilder] Added checkpoint for room #{chat_room.id} through position #{up_to_position}"
              )

              :telemetry.execute(
                [:app, :chat, :context, :checkpoint],
                %{
                  count: 1,
                  estimated_tokens_before: estimated_tokens,
                  estimated_tokens_after: estimate_text_tokens(summary),
                  compacted_message_count: length(checkpoint_chunk)
                },
                %{
                  chat_room_id: chat_room.id,
                  agent_id: agent.id,
                  up_to_position: up_to_position,
                  raw_tail_start_position: raw_tail_start_position
                }
              )

              {:ok, checkpoint_message}
            end
        end
    end
  end

  defp prompt_messages(canonical_messages, nil) do
    canonical_messages
    |> Enum.reject(&(message_role(&1) == "checkpoint"))
  end

  defp prompt_messages(canonical_messages, checkpoint) do
    [prompt_checkpoint_message(checkpoint) | uncovered_messages(canonical_messages, checkpoint)]
  end

  defp prompt_checkpoint_message(checkpoint) do
    content =
      [
        "Conversation checkpoint through message position #{checkpoint_up_to_position(checkpoint)}.",
        message_content(checkpoint)
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("\n\n")

    checkpoint
    |> normalize_prompt_message()
    |> Map.put(:content, content)
  end

  defp uncovered_messages(canonical_messages, checkpoint) do
    checkpoint_limit = checkpoint_up_to_position(checkpoint)

    Enum.reject(canonical_messages, fn message ->
      message_role(message) == "checkpoint" or
        (is_integer(checkpoint_limit) and is_integer(message_position(message)) and
           message_position(message) <= checkpoint_limit)
    end)
  end

  defp maybe_prune_tool_outputs(messages, policy, opts) do
    threshold_tokens = threshold_tokens(policy)
    extra_system_prompt = Keyword.get(opts, :extra_system_prompt, "")
    force_compaction? = Keyword.get(opts, :force_compaction, false)

    current_tokens = estimate_messages_tokens(messages, extra_system_prompt: extra_system_prompt)

    if current_tokens <= threshold_tokens and not force_compaction? do
      messages
    else
      tool_candidates = tool_pruning_candidates(messages, force_compaction?)

      Enum.reduce_while(tool_candidates, {messages, current_tokens}, fn index,
                                                                        {messages_acc, token_acc} ->
        if token_acc <= threshold_tokens do
          {:halt, {messages_acc, token_acc}}
        else
          pruned_message =
            messages_acc
            |> Enum.at(index)
            |> prune_tool_message(policy, force_compaction?)

          next_messages = List.replace_at(messages_acc, index, pruned_message)

          next_tokens =
            estimate_messages_tokens(next_messages, extra_system_prompt: extra_system_prompt)

          {:cont, {next_messages, next_tokens}}
        end
      end)
      |> elem(0)
    end
  end

  defp tool_pruning_candidates(messages, force_compaction?) do
    last_user_position =
      messages
      |> Enum.reverse()
      |> Enum.find_value(fn message ->
        if message_role(message) == "user", do: message_position(message)
      end)

    regular_candidates =
      messages
      |> Enum.with_index()
      |> Enum.filter(fn {message, _index} ->
        message_role(message) == "tool" and
          is_integer(message_position(message)) and
          is_integer(last_user_position) and
          message_position(message) < last_user_position
      end)
      |> Enum.map(&elem(&1, 1))

    forced_candidates =
      if force_compaction? do
        messages
        |> Enum.with_index()
        |> Enum.filter(fn {message, _index} -> message_role(message) == "tool" end)
        |> Enum.map(&elem(&1, 1))
      else
        []
      end

    Enum.uniq(regular_candidates ++ forced_candidates)
  end

  defp prune_tool_message(nil, _policy, _force_compaction?), do: nil

  defp prune_tool_message(message, policy, force_compaction?) do
    preview_chars =
      if force_compaction? do
        Map.get(policy, :force_tool_preview_chars)
      else
        Map.get(policy, :tool_preview_chars)
      end

    preview =
      message
      |> message_content()
      |> truncate_text(preview_chars)

    pruned_content =
      case String.trim(preview || "") do
        "" ->
          @old_tool_placeholder

        trimmed_preview ->
          @old_tool_placeholder <> "\n\nPreview:\n" <> trimmed_preview
      end

    Map.put(message, :content, pruned_content)
  end

  defp latest_checkpoint(messages) do
    messages
    |> Enum.filter(&(message_role(&1) == "checkpoint"))
    |> Enum.filter(&is_integer(checkpoint_up_to_position(&1)))
    |> Enum.max_by(
      fn checkpoint ->
        {checkpoint_up_to_position(checkpoint), message_position(checkpoint) || 0}
      end,
      fn -> nil end
    )
  end

  defp fallback_checkpoint_candidates(candidates, _messages_after_checkpoint, _force_compaction?)
       when candidates != [] do
    candidates
  end

  defp fallback_checkpoint_candidates([], messages_after_checkpoint, true) do
    emergency_checkpoint_candidates(messages_after_checkpoint)
  end

  defp fallback_checkpoint_candidates([], _messages_after_checkpoint, false), do: []

  defp emergency_checkpoint_candidates(messages_after_checkpoint) do
    case length(messages_after_checkpoint) do
      count when count > 1 -> Enum.take(messages_after_checkpoint, count - 1)
      _other -> []
    end
  end

  defp protected_start_index(messages, raw_tail_tokens) do
    count = length(messages)
    last_index = max(count - 1, 0)
    last_user_index = last_user_index(messages)

    computed_index =
      messages
      |> Enum.with_index()
      |> Enum.reverse()
      |> Enum.reduce_while({0, count}, fn {message, index}, {tokens, _start_index} ->
        message_tokens = estimate_message_tokens(message)

        cond do
          index == last_index ->
            {:cont, {tokens + message_tokens, index}}

          tokens + message_tokens <= raw_tail_tokens ->
            {:cont, {tokens + message_tokens, index}}

          true ->
            {:halt, {tokens, index + 1}}
        end
      end)
      |> elem(1)
      |> normalize_start_index(count)

    case last_user_index do
      nil -> computed_index
      user_index -> min(computed_index, user_index)
    end
  end

  defp normalize_start_index(index, count) when index >= count, do: 0
  defp normalize_start_index(index, _count), do: index

  defp last_user_index(messages) do
    messages
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find_value(fn {message, index} ->
      if message_role(message) == "user", do: index
    end)
  end

  defp take_from_start_by_tokens([], _limit), do: []

  defp take_from_start_by_tokens(messages, limit) do
    messages
    |> Enum.reduce_while({[], 0}, fn message, {selected, tokens} ->
      message_tokens = estimate_message_tokens(message)

      cond do
        selected == [] ->
          {:cont, {[message], tokens + message_tokens}}

        tokens + message_tokens <= limit ->
          {:cont, {selected ++ [message], tokens + message_tokens}}

        true ->
          {:halt, {selected, tokens}}
      end
    end)
    |> elem(0)
  end

  defp checkpoint_iterations(policy, true),
    do: Map.get(policy, :force_checkpoint_iterations, @default_policy.force_checkpoint_iterations)

  defp checkpoint_iterations(policy, false),
    do: Map.get(policy, :max_checkpoint_iterations, @default_policy.max_checkpoint_iterations)

  defp raw_tail_tokens(policy, true),
    do: Map.get(policy, :force_raw_tail_tokens, @default_policy.force_raw_tail_tokens)

  defp raw_tail_tokens(policy, false),
    do: Map.get(policy, :raw_tail_tokens, @default_policy.raw_tail_tokens)

  defp checkpoint_source_tokens(policy, true) do
    Map.get(
      policy,
      :force_checkpoint_source_tokens,
      @default_policy.force_checkpoint_source_tokens
    )
  end

  defp checkpoint_source_tokens(policy, false) do
    Map.get(policy, :checkpoint_source_tokens, @default_policy.checkpoint_source_tokens)
  end

  defp threshold_tokens(policy) do
    Map.get(policy, :context_window_tokens, @default_policy.context_window_tokens) -
      Map.get(policy, :reserve_tokens, @default_policy.reserve_tokens)
  end

  defp built_in_model_overrides(model) when is_binary(model) do
    cond do
      String.starts_with?(model, "google:gemini-2.5") ->
        %{
          context_window_tokens: 1_048_576,
          reserve_tokens: 32_768,
          raw_tail_tokens: 48_000,
          force_raw_tail_tokens: 24_000,
          checkpoint_source_tokens: 48_000,
          force_checkpoint_source_tokens: 64_000
        }

      String.starts_with?(model, "openai:gpt-4.1") ->
        %{
          context_window_tokens: 1_048_576,
          reserve_tokens: 32_768,
          raw_tail_tokens: 48_000,
          force_raw_tail_tokens: 24_000,
          checkpoint_source_tokens: 48_000,
          force_checkpoint_source_tokens: 64_000
        }

      String.starts_with?(model, "anthropic:") ->
        %{
          context_window_tokens: 200_000,
          reserve_tokens: 16_384,
          raw_tail_tokens: 32_000,
          force_raw_tail_tokens: 16_000,
          checkpoint_source_tokens: 32_000,
          force_checkpoint_source_tokens: 40_000
        }

      true ->
        %{}
    end
  end

  defp built_in_model_overrides(_model), do: %{}

  defp resolve_model_overrides(overrides, model) when is_map(overrides) and is_binary(model) do
    exact_override = Map.get(overrides, model, %{})

    prefix_override =
      overrides
      |> Enum.find_value(%{}, fn {prefix, value} ->
        if is_binary(prefix) and String.ends_with?(prefix, "*") do
          trimmed_prefix = String.trim_trailing(prefix, "*")
          if String.starts_with?(model, trimmed_prefix), do: value
        end
      end)

    exact_override
    |> Map.new()
    |> Map.merge(Map.new(prefix_override))
  end

  defp resolve_model_overrides(_overrides, _model), do: %{}

  defp normalize_prompt_message(%Message{} = message) do
    %{
      id: message.id,
      position: message.position,
      role: message.role,
      content: message.content,
      name: message.name,
      tool_call_id: message.tool_call_id,
      tool_calls: Message.tool_calls(message),
      metadata: message.metadata || %{}
    }
  end

  defp normalize_prompt_message(%{} = message) do
    %{
      id: Map.get(message, :id) || Map.get(message, "id"),
      position: Map.get(message, :position) || Map.get(message, "position"),
      role: to_string(Map.get(message, :role) || Map.get(message, "role") || "user"),
      content: Map.get(message, :content) || Map.get(message, "content"),
      name: Map.get(message, :name) || Map.get(message, "name"),
      tool_call_id: Map.get(message, :tool_call_id) || Map.get(message, "tool_call_id"),
      tool_calls:
        Map.get(message, :tool_calls, Map.get(message, "tool_calls", []))
        |> List.wrap(),
      metadata: Map.get(message, :metadata) || Map.get(message, "metadata") || %{}
    }
  end

  defp normalize_prompt_message(other) when is_binary(other) do
    %{role: "user", content: other, name: nil, tool_call_id: nil, tool_calls: [], metadata: %{}}
  end

  defp normalize_prompt_message(other) do
    %{
      role: "user",
      content: inspect(other),
      name: nil,
      tool_call_id: nil,
      tool_calls: [],
      metadata: %{}
    }
  end

  defp build_virtual_tool_call_turn_message(tool_call_turn, message) do
    %{
      role: "assistant",
      content: turn_content(tool_call_turn),
      tool_calls: turn_tool_calls(tool_call_turn),
      position: message.position,
      metadata: %{
        "synthetic" => true,
        "source_message_id" => message.id
      }
    }
  end

  defp build_virtual_tool_message(tool_response, message) do
    %{
      role: "tool",
      content: Map.get(tool_response, "content"),
      name: Map.get(tool_response, "name"),
      tool_call_id: Map.get(tool_response, "id"),
      position: message.position,
      metadata: %{
        "arguments" => Map.get(tool_response, "arguments"),
        "tool_status" => Map.get(tool_response, "status"),
        "synthetic" => true,
        "source_message_id" => message.id
      }
    }
  end

  defp estimate_message_tokens(message) do
    role = message_role(message)
    content = message_content(message)
    name = message_name(message)
    tool_call_id = message_tool_call_id(message)
    tool_calls = message_tool_calls(message)

    8 +
      estimate_text_tokens(role) +
      estimate_text_tokens(content) +
      estimate_text_tokens(name) +
      estimate_text_tokens(tool_call_id) +
      Enum.reduce(tool_calls, 0, fn tool_call, acc ->
        acc +
          estimate_text_tokens(Map.get(tool_call, "name") || Map.get(tool_call, :name)) +
          estimate_text_tokens(tool_call_arguments_text(tool_call))
      end)
  end

  defp estimate_text_tokens(nil), do: 0
  defp estimate_text_tokens(""), do: 0

  defp estimate_text_tokens(text) when is_binary(text) do
    div(byte_size(text) + 3, 4)
  end

  defp estimate_text_tokens(value) do
    value
    |> inspect()
    |> estimate_text_tokens()
  end

  defp message_role(%Message{} = message), do: message.role
  defp message_role(%{} = message), do: Map.get(message, :role) || Map.get(message, "role")
  defp message_role(_message), do: nil

  defp message_content(%Message{} = message), do: message.content

  defp message_content(%{} = message),
    do: Map.get(message, :content) || Map.get(message, "content")

  defp message_content(_message), do: nil

  defp message_name(%Message{} = message), do: message.name
  defp message_name(%{} = message), do: Map.get(message, :name) || Map.get(message, "name")
  defp message_name(_message), do: nil

  defp message_position(%Message{} = message), do: message.position

  defp message_position(%{} = message) do
    Map.get(message, :position) || Map.get(message, "position")
  end

  defp message_position(_message), do: nil

  defp checkpoint_up_to_position(nil), do: nil

  defp checkpoint_up_to_position(%Message{} = checkpoint) do
    checkpoint.metadata
    |> Kernel.||(%{})
    |> Map.get("up_to_position")
  end

  defp checkpoint_up_to_position(%{} = checkpoint) do
    checkpoint
    |> Map.get(:metadata, Map.get(checkpoint, "metadata", %{}))
    |> case do
      metadata when is_map(metadata) ->
        Map.get(metadata, "up_to_position") || Map.get(metadata, :up_to_position)

      _other ->
        nil
    end
  end

  defp message_tool_call_id(%Message{} = message), do: message.tool_call_id

  defp message_tool_call_id(%{} = message) do
    Map.get(message, :tool_call_id) || Map.get(message, "tool_call_id")
  end

  defp message_tool_call_id(_message), do: nil

  defp message_tool_calls(%Message{} = message), do: Message.tool_calls(message)

  defp message_tool_calls(%{} = message) do
    message
    |> Map.get(:tool_calls, Map.get(message, "tool_calls", []))
    |> List.wrap()
  end

  defp message_tool_calls(_message), do: []

  defp turn_content(%{} = tool_call_turn) do
    Map.get(tool_call_turn, "content") || Map.get(tool_call_turn, :content)
  end

  defp turn_tool_calls(%{} = tool_call_turn) do
    tool_call_turn
    |> Map.get("tool_calls", Map.get(tool_call_turn, :tool_calls, []))
    |> List.wrap()
  end

  defp tool_call_id(%{} = tool_call), do: Map.get(tool_call, "id") || Map.get(tool_call, :id)
  defp tool_call_id(_tool_call), do: nil

  defp tool_call_arguments_text(%{} = tool_call) do
    tool_call
    |> Map.get("arguments", Map.get(tool_call, :arguments))
    |> case do
      nil -> ""
      arguments -> Jason.encode!(arguments)
    end
  end

  defp tool_call_arguments_text(_tool_call), do: ""

  defp truncate_text(nil, _limit), do: ""

  defp truncate_text(text, limit) when is_binary(text) and is_integer(limit) and limit > 0 do
    if String.length(text) <= limit do
      text
    else
      String.slice(text, 0, limit) <> "..."
    end
  end

  defp truncate_text(text, _limit) when is_binary(text), do: text
  defp truncate_text(text, limit), do: text |> inspect() |> truncate_text(limit)

  defp compaction_module, do: Application.get_env(:app, :chat_compaction, App.Chat.Compaction)
end
