defmodule JidoMurmurWeb.Components.MessageInput do
  @moduledoc """
  Renders a chat message input with auto-resize and keyboard shortcuts.

  Includes a colocated JS hook (`.ChatInput`) that:
  - auto-resizes the textarea as the user types
  - submits on Enter (Shift+Enter for newline)
  - clears and resets height after submission

  ## Example

      <.message_input id="msg-form-session1" session_id={session.id} />
  """

  use Phoenix.Component

  import JidoMurmurWeb, only: [icon: 1]

  @doc """
  Renders a message input form.

  ## Attributes

    * `id` — Unique DOM ID for the form element.
    * `session_id` — The agent session ID (included as a hidden field).
      When nil, the form omits the hidden session_id field (useful for unified mode).
    * `on_submit` — Event name for form submission (default: `"send_message"`).
    * `placeholder` — Input placeholder text.
  """
  attr :id, :string, required: true
  attr :session_id, :string, default: nil
  attr :on_submit, :string, default: "send_message"
  attr :placeholder, :string, default: "Type a message…"

  def message_input(assigns) do
    ~H"""
    <div class="px-3 py-2 border-t border-base-300">
      <.form for={%{}} id={@id} phx-submit={@on_submit} class="chat-input-wrap">
        <%= if @session_id do %>
          <input type="hidden" name="message[session_id]" value={@session_id} />
        <% end %>
        <textarea
          id={"#{@id}-textarea"}
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
