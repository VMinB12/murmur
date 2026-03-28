defmodule <%= @app_module %>Web.Components.AgentHeader do
  @moduledoc """
  Renders the header bar for an agent column.
  """

  use Phoenix.Component

  import <%= @app_module %>Web.CoreComponents, only: [icon: 1]

  attr :session, :map, required: true
  attr :color, :map, required: true
  attr :status, :atom, default: :idle
  attr :on_remove, :string, default: "remove_agent"

  def agent_header(assigns) do
    ~H"""
    <div class={[
      "flex items-center justify-between px-3 py-2 border-b",
      @color.header
    ]}>
      <div class="flex items-center gap-2 min-w-0">
        <div class={["w-2 h-2 rounded-full shrink-0", @color.dot]}></div>
        <span class="font-medium text-sm truncate">{@session.display_name}</span>
        <span class="text-xs opacity-60 shrink-0">{@session.agent_profile_id}</span>
      </div>
      <div class="flex items-center gap-1 shrink-0">
        <%%= if @status == :busy do %>
          <span class="loading loading-dots loading-xs text-warning"></span>
        <%% end %>
        <button
          phx-click={@on_remove}
          phx-value-session-id={@session.id}
          data-confirm="Remove this agent? Chat history will be preserved."
          class="btn btn-ghost btn-xs opacity-40 hover:opacity-100"
        >
          <.icon name="hero-x-mark" class="w-3 h-3" />
        </button>
      </div>
    </div>
    """
  end
end
