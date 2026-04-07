defmodule AppWeb.ChatComponents do
  use AppWeb, :html

  attr :form, :any, required: true
  attr :form_id, :string, default: "chat-message-form"
  attr :textarea_id, :string, default: "chat-message-input"
  attr :composer_id, :string, default: "chat-composer-shell"
  attr :controls_id, :string, default: "chat-message-controls"
  attr :change_event, :string, default: "validate"
  attr :submit_event, :string, default: "send"
  attr :cancel_event, :string, default: "cancel-stream"
  attr :layout_target_id, :string, default: nil
  attr :streaming, :boolean, default: false
  slot :controls

  def chat_message_composer(assigns) do
    ~H"""
    <.form
      for={@form}
      id={@form_id}
      phx-change={@change_event}
      phx-submit={@submit_event}
      data-streaming={to_string(@streaming)}
    >
      <div
        id={@composer_id}
        data-chat-composer-shell
        class="overflow-hidden rounded-lg rounded-b-none border-4 border-b-0 border-border/70 bg-background/80 backdrop-blur-lg supports-[backdrop-filter]:bg-background/60"
      >
        <.textarea
          field={@form[:content]}
          id={@textarea_id}
          rows="1"
          placeholder="Message… (Enter to send, Shift+Enter for new line)"
          phx-hook=".ChatInput"
          data-layout-target={@layout_target_id}
          data-composer-offset-padding="24"
          class="field-sizing-content max-h-[50vh] resize-none overflow-y-auto !rounded-none !border-0 !bg-transparent !px-4 !pb-3 !pt-4 !shadow-none placeholder:text-muted-foreground/75 focus-visible:!border-transparent focus-visible:!ring-0"
        />
        <div id={@controls_id} class="flex items-center gap-3 px-4 py-2">
          {render_slot(@controls)}
          <button
            id="chat-message-submit"
            type={if @streaming, do: "button", else: "submit"}
            phx-click={if @streaming, do: @cancel_event, else: nil}
            class={[
              "group ml-auto flex size-11 items-center justify-center rounded-2xl bg-primary p-0 text-primary-foreground shadow-sm transition-colors hover:bg-primary/90",
              if(@streaming, do: "hover:bg-destructive", else: "")
            ]}
            aria-label={if @streaming, do: "Stop generating", else: "Send message"}
            title={if @streaming, do: "Stop generating", else: "Send message"}
          >
            <%= if @streaming do %>
              <span class="relative flex size-4 items-center justify-center">
                <.icon
                  name="hero-arrow-path"
                  class="size-4 animate-spin text-current transition-opacity group-hover:opacity-0"
                />
                <.icon
                  name="hero-stop"
                  class="absolute size-4 text-current opacity-0 transition-opacity group-hover:opacity-100"
                />
              </span>
            <% else %>
              <.icon
                name="hero-paper-airplane"
                class="size-4 text-current transition-transform group-hover:-translate-y-0.5 group-hover:translate-x-0.5"
              />
            <% end %>
          </button>
        </div>
      </div>
    </.form>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".ChatInput">
      export default {
        mounted() {
          this.syncComposerOffset = () => {
            const layoutId = this.el.dataset.layoutTarget;
            if (!layoutId) return;

            const layout = document.getElementById(layoutId);
            const composerShell = this.el.closest("form")?.querySelector("[data-chat-composer-shell]");

            if (!layout || !composerShell) return;

            const padding = Number.parseInt(this.el.dataset.composerOffsetPadding || "24", 10);
            const offset = Math.ceil(composerShell.getBoundingClientRect().height + padding);
            layout.style.setProperty("--chat-composer-offset", `${offset}px`);
          };

          this.onInput = () => this.syncComposerOffset();
          this.onResize = () => this.syncComposerOffset();
          this.onKeyDown = (event) => {
            if (event.key === "Enter" && !event.shiftKey) {
              event.preventDefault();
              const form = this.el.closest("form");
              if (!form || form.dataset.streaming === "true") return;

              if (typeof form.requestSubmit === "function") {
                form.requestSubmit();
              } else {
                form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
              }
            }
          };

          this.el.addEventListener("input", this.onInput);
          this.el.addEventListener("keydown", this.onKeyDown);
          window.addEventListener("resize", this.onResize);
          this.syncComposerOffset();
        },

        updated() {
          this.syncComposerOffset();
        },

        destroyed() {
          this.el.removeEventListener("input", this.onInput);
          this.el.removeEventListener("keydown", this.onKeyDown);
          window.removeEventListener("resize", this.onResize);
        }
      }
    </script>
    """
  end

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
