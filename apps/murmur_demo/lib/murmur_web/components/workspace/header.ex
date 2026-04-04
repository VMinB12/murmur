defmodule MurmurWeb.Components.Workspace.Header do
  @moduledoc false
  use MurmurWeb, :html

  @doc "Renders the workspace header controls."
  attr :workspace, :map, required: true
  attr :agent_sessions, :list, required: true
  attr :view_mode, :atom, required: true
  attr :show_task_board, :boolean, required: true

  def workspace_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between px-2 py-3 border-b border-base-300">
      <div class="flex items-center gap-3">
        <.link navigate={~p"/workspaces"} class="btn btn-ghost btn-sm">
          <.icon name="hero-arrow-left" class="w-4 h-4" />
        </.link>
        <div class="space-y-0.5">
          <h1 class="text-lg font-semibold tracking-tight">{@workspace.name}</h1>
          <span class="text-xs text-base-content/50">{length(@agent_sessions)} agent(s)</span>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <%= if @agent_sessions != [] do %>
          <div class="join border border-base-300 rounded-lg overflow-hidden">
            <button
              id="view-split-btn"
              phx-click="toggle_view_mode"
              class={[
                "btn btn-ghost btn-xs join-item border-0 rounded-none",
                if(@view_mode == :split, do: "bg-base-300", else: "opacity-50")
              ]}
              title="Split view"
            >
              <.icon name="hero-view-columns" class="w-4 h-4" />
            </button>
            <button
              id="view-unified-btn"
              phx-click="toggle_view_mode"
              class={[
                "btn btn-ghost btn-xs join-item border-0 rounded-none",
                if(@view_mode == :unified, do: "bg-base-300", else: "opacity-50")
              ]}
              title="Unified view"
            >
              <.icon name="hero-chat-bubble-left-right" class="w-4 h-4" />
            </button>
          </div>
          <button
            id="toggle-task-board-btn"
            phx-click="toggle_task_board"
            class={[
              "btn btn-ghost btn-sm",
              if(@show_task_board, do: "text-primary", else: "text-base-content/60")
            ]}
            title="Task Board"
          >
            <.icon name="hero-clipboard-document-check" class="w-4 h-4" /> Tasks
          </button>
          <button
            id="clear-team-btn"
            phx-click="clear_team"
            data-confirm="Clear all conversations? This cannot be undone."
            class="btn btn-ghost btn-sm text-error/70 hover:text-error"
          >
            <.icon name="hero-trash" class="w-4 h-4" /> Clear
          </button>
        <% end %>
        <button
          class="btn btn-primary btn-sm"
          onclick="document.getElementById('add-agent-dialog').showModal()"
        >
          <.icon name="hero-plus" class="w-4 h-4" /> Add Agent
        </button>
      </div>
    </div>
    """
  end
end
