# Plan: Agent Feature & UI Improvements

**Date:** 2026-03-10
**Goal:** Add agent/chatroom system, improve sidebar, swap jido→req_llm

---

## Phase 1: Dependencies & Cleanup

### 1.1 Remove Jido
- [ ] Remove `{:jido, "~> 1.0"}` from `mix.exs`
- [ ] Remove `config :app, App.Jido` from `config/config.exs`
- [ ] Remove `App.Jido` from supervision tree in `lib/app/application.ex`
- [ ] Delete `lib/app/jido.ex`
- [ ] Run `mix deps.get`

### 1.2 Add req_llm
- [ ] Add `{:req_llm, "~> 1.6"}` to `mix.exs`
- [ ] Run `mix deps.get`
- [ ] Configure `config :req_llm, load_dotenv: false` (we manage keys in DB via providers)

---

## Phase 2: UI — Sidebar & Layout Improvements

### 2.1 Add Provider link to sidebar
In `lib/app_web/components/layouts.ex` `dashboard/1`:
- [ ] Add `<.link navigate={~p"/providers"}>` to sidebar nav (with `hero-server-stack` icon)

### 2.2 Move user menu from top header to sidebar (PUI Dropdown)
- [ ] **Remove** the user info + dropdown from the `<header>` section (lines ~219–251)
- [ ] **Replace** the static user section at sidebar bottom (lines ~294–304) with a PUI `<.menu_button>` dropdown
  - Show user email + icon
  - Items: Settings (navigate), Log out (href with method delete)
- [ ] The header should keep: hamburger toggle, logo, theme toggle (no user info)

### 2.3 Add Agents link to sidebar
- [ ] Add `<.link navigate={~p"/agents"}>` to sidebar nav (with `hero-cpu-chip` icon)
- [ ] Add `<.link navigate={~p"/chat"}>` to sidebar nav (with `hero-chat-bubble-left-right` icon)

---

## Phase 3: Database — Agent & Chat Schemas

### 3.1 Agents table migration
```
mix ecto.gen.migration create_agents
```

```elixir
create table(:agents, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :name, :string, null: false
  add :system_prompt, :text
  add :model, :string, null: false          # e.g. "anthropic:claude-haiku-4-5"
  add :provider_id, references(:providers, type: :binary_id, on_delete: :restrict), null: false
  add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
  add :extra_params, :map, default: %{}     # temperature, max_tokens, etc.
  add :tools, {:array, :string}, default: [] # list of builtin tool names e.g. ["web_fetch"]

  timestamps(type: :utc_datetime)
end

create index(:agents, [:user_id])
create index(:agents, [:provider_id])
```

### 3.2 Chat rooms table migration
```
mix ecto.gen.migration create_chat_rooms
```

```elixir
create table(:chat_rooms, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :title, :string
  add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

  timestamps(type: :utc_datetime)
end

create index(:chat_rooms, [:user_id])
```

### 3.3 Chat room agents (join table)
```
mix ecto.gen.migration create_chat_room_agents
```

```elixir
create table(:chat_room_agents, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :chat_room_id, references(:chat_rooms, type: :binary_id, on_delete: :delete_all), null: false
  add :agent_id, references(:agents, type: :binary_id, on_delete: :cascade), null: false
  add :is_commander, :boolean, default: false  # the orchestrator/default agent

  timestamps(type: :utc_datetime)
end

create index(:chat_room_agents, [:chat_room_id])
create index(:chat_room_agents, [:agent_id])
create unique_index(:chat_room_agents, [:chat_room_id, :agent_id])
```

### 3.4 Chat messages table
```
mix ecto.gen.migration create_chat_messages
```

```elixir
create table(:chat_messages, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :chat_room_id, references(:chat_rooms, type: :binary_id, on_delete: :delete_all), null: false
  add :role, :string, null: false              # "user", "assistant", "system", "tool"
  add :content, :text
  add :agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)  # which agent responded
  add :metadata, :map, default: %{}            # tool calls, usage data, etc.

  timestamps(type: :utc_datetime)
end

create index(:chat_messages, [:chat_room_id])
create index(:chat_messages, [:agent_id])
```

---

## Phase 4: Context Modules (Business Logic)

### 4.1 `App.Agents` context — `lib/app/agents.ex`
Functions:
- `list_agents(scope)` — list all agents for user
- `get_agent!(scope, id)` — get agent with preloaded provider
- `create_agent(scope, attrs)` — create agent, validate provider ownership
- `update_agent(scope, agent, attrs)`
- `delete_agent(scope, agent)`
- `change_agent(agent, attrs \\ %{})`

### 4.2 `App.Agents.Agent` schema — `lib/app/agents/agent.ex`
Fields: name, system_prompt, model, provider_id, user_id, extra_params (map), tools (array of strings)
- `belongs_to :user`
- `belongs_to :provider, App.Providers.Provider`
- Changeset validates: name required, model required, provider_id required
- `tools` validated against known builtins: `["web_fetch"]`

### 4.3 `App.Chat` context — `lib/app/chat.ex`
Functions:
- `list_chat_rooms(scope)` — list chat rooms for user (preload agents)
- `get_chat_room!(scope, id)` — get chat room with agents + messages preloaded
- `create_chat_room(scope, attrs)` — create room, assign agents
- `delete_chat_room(scope, chat_room)`
- `add_agent_to_room(scope, chat_room, agent_id, opts \\ [])` — opts: `is_commander`
- `remove_agent_from_room(scope, chat_room, agent_id)`
- `list_messages(chat_room)` — ordered by inserted_at
- `create_message(chat_room, attrs)` — create a message
- `send_message(scope, chat_room, content)` — orchestrate: save user msg → pick agent → call LLM → save response → return

### 4.4 `App.Chat.ChatRoom` schema — `lib/app/chat/chat_room.ex`
- `has_many :chat_room_agents`
- `has_many :agents, through: [:chat_room_agents, :agent]`
- `has_many :messages, App.Chat.Message`

### 4.5 `App.Chat.ChatRoomAgent` schema — `lib/app/chat/chat_room_agent.ex`
- `belongs_to :chat_room`
- `belongs_to :agent, App.Agents.Agent`
- field `is_commander`, `:boolean`

### 4.6 `App.Chat.Message` schema — `lib/app/chat/message.ex`
- `belongs_to :chat_room`
- `belongs_to :agent, App.Agents.Agent` (nullable — nil for user msgs)
- fields: role, content, metadata

---

## Phase 5: Agent Runtime — LLM Integration

### 5.1 `App.Agents.Runner` — `lib/app/agents/runner.ex`
Core module that executes an agent:

```elixir
defmodule App.Agents.Runner do
  @moduledoc "Executes an agent against a conversation context using ReqLLM."

  alias App.Agents.Agent
  alias App.Agents.Tools

  def run(%Agent{} = agent, messages, opts \\ []) do
    model_spec = agent.model
    api_key = agent.provider.api_key

    context = build_context(agent, messages)
    tools = Tools.resolve(agent.tools)

    llm_opts =
      [api_key: api_key, tools: tools]
      |> merge_extra_params(agent.extra_params)
      |> Keyword.merge(opts)

    case Keyword.get(opts, :stream, false) do
      true -> ReqLLM.stream_text(model_spec, context, llm_opts)
      false -> ReqLLM.generate_text(model_spec, context, llm_opts)
    end
  end

  defp build_context(agent, messages) do
    msgs =
      [ReqLLM.Context.system(agent.system_prompt || "You are a helpful assistant.")] ++
        Enum.map(messages, fn msg ->
          case msg.role do
            "user" -> ReqLLM.Context.user(msg.content)
            "assistant" -> ReqLLM.Context.assistant(msg.content)
            "system" -> ReqLLM.Context.system(msg.content)
            _ -> ReqLLM.Context.user(msg.content)
          end
        end)

    ReqLLM.Context.new(msgs)
  end

  defp merge_extra_params(opts, nil), do: opts
  defp merge_extra_params(opts, extra) when extra == %{}, do: opts
  defp merge_extra_params(opts, extra) do
    extra
    |> Enum.reduce(opts, fn {k, v}, acc ->
      Keyword.put(acc, String.to_existing_atom(k), v)
    end)
  end
end
```

### 5.2 `App.Agents.Tools` — `lib/app/agents/tools.ex`
Registry of builtin tools:

```elixir
defmodule App.Agents.Tools do
  @moduledoc "Registry of builtin agent tools."

  @builtin_tools %{
    "web_fetch" => fn ->
      ReqLLM.tool(
        name: "web_fetch",
        description: "Fetch the content of a web page given a URL. Returns the text body.",
        parameters: [
          url: [type: :string, required: true, doc: "The URL to fetch"]
        ],
        callback: {__MODULE__, :do_web_fetch}
      )
    end
  }

  def available_tools, do: Map.keys(@builtin_tools)

  def resolve(tool_names) when is_list(tool_names) do
    tool_names
    |> Enum.filter(&Map.has_key?(@builtin_tools, &1))
    |> Enum.map(fn name -> Map.fetch!(@builtin_tools, name).() end)
  end

  def do_web_fetch(%{url: url}) do
    case Req.get(url) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}
      {:ok, %Req.Response{status: status}} ->
        {:error, "HTTP #{status}"}
      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end
end
```

### 5.3 `App.Chat.Orchestrator` — `lib/app/chat/orchestrator.ex`
Handles multi-agent room logic:
- For single-agent rooms: directly run the agent
- For multi-agent rooms: run the commander agent with tool to delegate to other agents
  - The commander gets a system prompt extension listing available agents
  - Commander can call `delegate_to_agent` tool to hand off

```elixir
defmodule App.Chat.Orchestrator do
  alias App.Agents.Runner
  alias App.Chat

  def send_message(scope, chat_room, content) do
    # 1. Save user message
    {:ok, user_msg} = Chat.create_message(chat_room, %{role: "user", content: content})

    # 2. Get all messages for context
    messages = Chat.list_messages(chat_room)

    # 3. Determine which agent to use
    agents = chat_room.chat_room_agents
    commander = Enum.find(agents, & &1.is_commander) || List.first(agents)
    agent = commander.agent

    # 4. Run agent
    case Runner.run(agent, messages) do
      {:ok, response} ->
        text = ReqLLM.Response.text(response)
        {:ok, assistant_msg} = Chat.create_message(chat_room, %{
          role: "assistant",
          content: text,
          agent_id: agent.id,
          metadata: %{usage: response.usage}
        })
        {:ok, assistant_msg}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

---

## Phase 6: LiveView Pages

### 6.1 Agent Index — `lib/app_web/live/agent_live/index.ex` + `.html.heex`
- List agents in a table/card layout using streams
- "New Agent" button → modal form
- Edit/Delete actions
- Uses `Layouts.dashboard`

### 6.2 Agent Form Component — `lib/app_web/live/agent_live/form_component.ex`
Fields:
- Name (text input)
- System Prompt (textarea)
- Provider (select from user's providers)
- Model (text input — format `provider:model-name`)
- Extra Params: temperature (number), max_tokens (number)
- Tools (multi-checkbox for available builtin tools)

### 6.3 Chat Index — `lib/app_web/live/chat_live/index.ex` + `.html.heex`
- List chat rooms with title, agent count, last message preview
- "New Chat" button → form to select agent(s) and title
- Delete chat room

### 6.4 Chat Room — `lib/app_web/live/chat_live/show.ex` + `.html.heex`
- Chat UI with message stream
- Input box at bottom
- Messages rendered with role indicators (user vs agent)
- Agent name shown on assistant messages
- Send message triggers orchestrator → response appended to stream
- Streaming support (nice-to-have, can start with non-streaming)

### 6.5 Routes
In router.ex, add to `:require_authenticated_user` live_session:
```elixir
live "/agents", AgentLive.Index, :index
live "/agents/new", AgentLive.Index, :new
live "/agents/:id/edit", AgentLive.Index, :edit
live "/chat", ChatLive.Index, :index
live "/chat/new", ChatLive.Index, :new
live "/chat/:id", ChatLive.Show, :show
```

---

## Phase 7: Testing

### 7.1 Unit tests
- `test/app/agents_test.exs` — CRUD for agents
- `test/app/chat_test.exs` — CRUD for chat rooms, messages
- `test/app/agents/tools_test.exs` — tool resolution, web_fetch

### 7.2 LiveView tests
- `test/app_web/live/agent_live_test.exs` — list, create, delete agents
- `test/app_web/live/chat_live_test.exs` — list, create rooms, send messages

---

## Implementation Order

1. **Phase 1** — Remove jido, add req_llm
2. **Phase 3** — Database migrations
3. **Phase 4** — Context modules & schemas
4. **Phase 5** — Agent runtime (Runner, Tools, Orchestrator)
5. **Phase 2** — UI sidebar improvements
6. **Phase 6** — LiveView pages (agents, then chat)
7. **Phase 7** — Tests

---

## File Summary

### New files:
- `lib/app/agents.ex`
- `lib/app/agents/agent.ex`
- `lib/app/agents/runner.ex`
- `lib/app/agents/tools.ex`
- `lib/app/chat.ex`
- `lib/app/chat/chat_room.ex`
- `lib/app/chat/chat_room_agent.ex`
- `lib/app/chat/message.ex`
- `lib/app/chat/orchestrator.ex`
- `lib/app_web/live/agent_live/index.ex`
- `lib/app_web/live/agent_live/index.html.heex`
- `lib/app_web/live/agent_live/form_component.ex`
- `lib/app_web/live/chat_live/index.ex`
- `lib/app_web/live/chat_live/index.html.heex`
- `lib/app_web/live/chat_live/show.ex`
- `lib/app_web/live/chat_live/show.html.heex`
- 4 migration files

### Modified files:
- `mix.exs` — remove jido, add req_llm
- `config/config.exs` — remove jido config, add req_llm config
- `lib/app/application.ex` — remove App.Jido from supervision tree
- `lib/app_web/router.ex` — add agent & chat routes
- `lib/app_web/components/layouts.ex` — sidebar improvements

### Deleted files:
- `lib/app/jido.ex`
