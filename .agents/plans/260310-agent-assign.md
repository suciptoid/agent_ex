# Chatroom Agent Handler
- refactor commander system (commander_agent_id) on chatroom (also update the ui) and replace with: active agent id. during creating chatroom first agent added is active agent, or user can select which agent to make active if has multiple agents.
- create internal tool for agents called `handover` to make active agent select another agent to make active on the chatroom
- only active agent can has `handover` tool
- active agent can request other agent in the chatroom to response request, then assigned agent should respond and create a new message on behalf of the agent, not the active agent. example:
  - user: ask AgentA to fetch content site.com/file.txt
  - ActiveAgent: tool calll -> ask(AgentA): fetch content site.com/file.txt
  - AgentA: ok i will fetch it (with tool call web_fetch(site.com/file.txt))
  - AgentA: ok here is the content ...

# UI Improvements
- remove top header, main layout is [sidebar|content]
- hamburger menu and app logo + name on top of sidebar
- theme toggle hidden under user menu popup/dropdown
- dashboard content layout not overflow-y auto, overflow handled on content (child)

## Chat UI
- remove border bottom / line in chat messages
- reduce padding on chat bubble
- wrap whitespace on chat bubble
- reduce padding on chat input box
- remove "The full room history is persisted and sent back to the selected agent on every turn." area
- align send button on the right of chat input box (floating on bottom right if chat input is autosized)
- change send button using only icons (send icon, heroicon)
- chat title only one line [<- Back to chat | Title <spacing> | agents lists], no more "Messages are routed .."
- tool call response collapsible, default closed

## Chat Streaming UI
- currently chat response not realtime streaming into ui, caused by ReqLLM.Response.text
- read docs about handle streaming per token arrive: https://hexdocs.pm/req_llm/ReqLLM.Generation.html#stream_text/3
- before llm requested, create placeholder chat with empty message, with status is :requesting
- during streaming, update ui incrementally with each token received, debounce write udpate for that message into db per 5-10 tokens, to avoid spamming db writes. also change message status to :streaming while updating.
- after streaming completes, change message status to :completed and write final text into db
- so this task need refactor message.ex schema to add enum :status to track message state (requesting, streaming, completed, error)

# Phase 2 Feedback
- llm response still not realtime streaming to ui
  - still use ReqLLM.Response.text, this method will wait stream until finished, not realtime udpate per token to UI
  - the docs says:
  - {:ok, response} = ReqLLM.Generation.stream_text("anthropic:claude-3-sonnet", "Tell me a story")
      ReqLLM.Response.text_stream(response) |> Enum.each(&IO.write/1)
      
      # Access usage metadata after streaming
      ReqLLM.Response.usage(response)
      #=> %{input_tokens: 15, output_tokens: 42}
- send icon color is not visible
- during calling ask_agent, active agent (caller) should not wait the resposne. 
  - example 1:
  - user: ask agent1 to fetch data from site.com/data.txt
  - active_agent: <since user prompt with ask, user give command to active_agent, active_agent can reply with some text reason, or just call tool ask_agent to fetch data async>
  - active_agent: i'll ask agent1 to fetch data from site.com/data.txt
  - active_agent: tool_call ask_agent(agent1, "fetch data from site.com/data.txt")
  - agent1: tool_call: web_fetch site.com/data.txt
  - tool_response: <this response belongs to agent1>
  - agent1: the data from site.com/data.txt is ....
  - <stop loop/finish>
  - example 2:
  - user: @agent1, fetch data from site.com/data.txt
  - active_agent: tool_call ask_agent(agent1, "fetch data from site.com/data.txt")
  - agent1: tool_call: web_fetch site.com/data.txt
  - tool_response: xxxx
  - agent1: the data from site.com/data.txt is xxxx
