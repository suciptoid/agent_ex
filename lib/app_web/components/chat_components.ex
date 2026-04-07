defmodule AppWeb.ChatComponents do
  use AppWeb, :html

  attr :id, :string, required: true
  attr :selected_agents, :list, required: true
  attr :unselected_agents, :list, default: []
  attr :active_agent_id, :string, default: nil
  attr :set_active_event, :string, required: true
  attr :remove_event, :string, required: true
  attr :add_event, :string, required: true
  attr :allow_remove_last, :boolean, default: false
  attr :active_label, :string, default: "active"
  attr :class, :string, default: ""

  def chat_agent_selector(assigns) do
    ~H"""
    <div id={@id} class={["flex flex-wrap items-center gap-1.5", @class]}>
      <div
        :for={agent <- @selected_agents}
        class={[
          "group/badge inline-flex items-center gap-1 rounded-full border px-2.5 py-1 text-sm font-medium transition-colors",
          if(agent.id == @active_agent_id,
            do: "border-primary/30 bg-primary/10 text-primary",
            else: "border-border bg-background text-foreground/80"
          )
        ]}
      >
        <button
          id={"#{@id}-set-#{agent.id}"}
          type="button"
          phx-click={@set_active_event}
          phx-value-id={agent.id}
          class="inline-flex items-center gap-1"
          title={if(agent.id == @active_agent_id, do: "Current agent", else: "Set as active")}
        >
          <.icon name="hero-cpu-chip" class="size-3.5" />
          <span class="max-w-40 truncate">{agent.name}</span>
          <span
            :if={agent.id == @active_agent_id}
            class="rounded-full bg-current/10 px-1.5 py-0.5 text-[10px] font-medium leading-none"
          >
            {@active_label}
          </span>
        </button>

        <button
          :if={@allow_remove_last or length(@selected_agents) > 1}
          id={"#{@id}-remove-#{agent.id}"}
          type="button"
          phx-click={@remove_event}
          phx-value-id={agent.id}
          class="inline-flex size-5 items-center justify-center rounded-full text-current opacity-0 transition hover:bg-destructive/20 hover:text-destructive group-hover/badge:opacity-100"
          title="Remove agent"
        >
          <.icon name="hero-x-mark" class="size-3.5" />
        </button>
      </div>

      <%= if @unselected_agents != [] do %>
        <.menu_button
          id={"#{@id}-add-agent"}
          variant="outline"
          content_class="w-56"
          class="h-auto gap-1.5 rounded-full border-dashed bg-background px-2.5 py-1 text-sm font-normal text-muted-foreground shadow-none transition-colors hover:border-primary/40 hover:bg-background hover:text-foreground"
        >
          <.icon name="hero-plus" class="size-3.5" /> Add agent
          <:items>
            <.menu_item
              :for={agent <- @unselected_agents}
              phx-click={@add_event}
              phx-value-id={agent.id}
            >
              <.icon name="hero-cpu-chip" class="size-4 text-muted-foreground" />
              <span class="min-w-0 flex-1 truncate text-left">{agent.name}</span>
            </.menu_item>
          </:items>
        </.menu_button>
      <% else %>
        <button
          id={"#{@id}-add-agent-trigger"}
          type="button"
          disabled
          class="inline-flex items-center gap-1.5 rounded-full border border-dashed border-border bg-muted/40 px-2.5 py-1 text-sm text-muted-foreground/70"
        >
          <.icon name="hero-plus" class="size-3.5" /> Add agent
        </button>
      <% end %>
    </div>
    """
  end
end
