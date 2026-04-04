defmodule <%= @app_module %>Web.Components.MessageInput do
  @moduledoc """
  Renders a chat message input with auto-resize and keyboard shortcuts.
  """

  use Phoenix.Component

  import <%= @app_module %>Web.CoreComponents, only: [icon: 1]

  attr :id, :string, required: true
  attr :session_id, :string, default: nil
  attr :on_submit, :string, default: "send_message"
  attr :placeholder, :string, default: "Type a message…"
  attr :input_id, :string, default: nil
  attr :container_class, :string, default: "px-3 py-2 border-t border-base-300"

  def message_input(assigns) do
    assigns = assign(assigns, :resolved_input_id, assigns.input_id || "#{assigns.id}-textarea")

    ~H"""
    <div class={@container_class}>
      <.form for={%%{}} id={@id} phx-submit={@on_submit} class="chat-input-wrap">
        <%%= if @session_id do %>
          <input type="hidden" name="message[session_id]" value={@session_id} />
        <%% end %>
        <textarea
          id={@resolved_input_id}
          name="message[content]"
          placeholder={@placeholder}
          autocomplete="off"
          rows="1"
          class="chat-input"
          phx-hook=".ChatInput"
        />
        <button type="submit" class="chat-send-btn" aria-label="Send message">
          <.icon name="hero-paper-airplane" class="w-4 h-4" />
        </button>
      </.form>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ChatInput">
        export default {
          mounted() {
            this.form = this.el.closest("form")
            this.el.addEventListener("input", () => this.resize())
            this.el.addEventListener("keydown", (e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault()
                if (this.el.value.trim() !== "") {
                  this.form.requestSubmit()
                }
              }
            })
            this.form.addEventListener("submit", () => {
              requestAnimationFrame(() => {
                this.form.reset()
                this.resize()
              })
            })
          },
          resize() {
            this.el.style.height = "auto"
            const max = 6 * parseFloat(getComputedStyle(this.el).lineHeight || 20)
            this.el.style.height = Math.min(this.el.scrollHeight, max) + "px"
          }
        }
      </script>
    </div>
    """
  end
end
