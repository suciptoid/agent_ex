# Message Handling
- change into enum, :pending, :streaming, :error, :completed from field :status, :string, default: "completed"
- when streaming error, update status to :error and content to error message
- add regenerate button (with icon sync/2 arrow circle), when message status is :completed, tooltip is "Regenerate" and when message status is :error, tooltip is "Retry". change status to :pending back, and clear content
- add estimated cost on each message, only show on message is hovered
- chat list ui, show with list 1 column, delete button make it smaller with only icon

# LLM Streaming
- Also save thinking response, add to message fields
- show thinking response on ui, like the streaming content, but different background and collapsible
- tool response still not visible on the ui, it should be shown during streaming and default to collapse if has new message
example 1:
user: fetch data from hello.com/data.txt
agent: i will fetch the data (tool_call: web_fetch(hello.com/data.txt))
(|>) response (collapsed, since has new message)
user: make it in table formatted
agent: here is the table...

example 2:
user: search current gold price
agent: i will search the gold price (tool_call: web_search(gold price))
(v) response (expaned, since it's last message)

- thinking response ui, same as tool response ui but different background color

- run_with_tool_loop still using ReqLLM.generate_text and ReqLLM.Response.text, update to ReqLLM.generate_stream

# Agent UI
- agent list don't show prompt preview, edit and delete button use icons (heroicons)
