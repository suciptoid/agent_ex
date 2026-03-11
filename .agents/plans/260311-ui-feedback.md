# UI Improvements Feedback
- replace all dialog/modal using PUI.Dialog, e.g New Agent dialog, edit agent dialog, new chat dialog, etc.
- tool response & thinking ui is before content (currently after content)
- tool response default to collapsed, add spinner icon when still calling/streaming tool function
- thinking only expanded when content is not ready to be streamed, if
  content already streaming, thinking and tool response should be collapsed
- when message has tool call / thinking ui, sometimes autoscroll is not working
- when chatroom is streaming, the send button has no icon because phx-disable-with="". change to spiner icon, with animate-spin class, when button is hovered, change icon to stop icon, and when pressed, cancel the stream.

# Tool calling
Ensure tool calling placeholder is create before awaiting the tool function response, so the UI is not broken when the tool function takes a long time to respond.

# Chatroom Layout
Autoscroll on chatroom is glitch when chatroom already has history: 
open chatroom -> load message -> scrolling to bottom. the UX should be, open chatroom -> visible the last message.

i've previously create this kind of chatroom, with example code:

<div
    :if={@messages != []}
    id={"room-#{if @room, do: @room.id, else: "new"}"}
    phx-hook="ChatRoom"
    class="message-list flex-1 overflow-y-auto flex flex-col-reverse"
>

using flex-col-revers, ensure the data order is correct.

after this update, make sure collapsing thinking/tool response sections works correctly (no scroll jump)
