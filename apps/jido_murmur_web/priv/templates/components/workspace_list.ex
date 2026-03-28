defmodule <%= @app_module %>Web.Components.WorkspaceList do
  @moduledoc """
  Renders a workspace listing for navigation.
  """

  use Phoenix.Component

  import <%= @app_module %>Web.CoreComponents, only: [icon: 1]

  attr :workspaces, :list, required: true
  attr :href_fn, :any, default: nil

  def workspace_list(assigns) do
    ~H"""
    <div class="space-y-2">
      <%%= if @workspaces == [] do %>
        <div class="text-center text-base-content/40 py-8">
          <.icon name="hero-folder-open" class="w-8 h-8 mx-auto mb-2 opacity-40" />
          <p class="text-sm">No workspaces yet</p>
        </div>
      <%% else %>
        <%%= for workspace <- @workspaces do %>
          <.link
            navigate={workspace_href(@href_fn, workspace)}
            class="block px-4 py-3 rounded-lg border border-base-300/50 hover:bg-base-200/50 transition-colors group"
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-3 min-w-0">
                <.icon name="hero-chat-bubble-left-right" class="w-5 h-5 text-base-content/40 shrink-0" />
                <span class="font-medium text-sm truncate">{workspace.name}</span>
              </div>
              <.icon name="hero-chevron-right" class="w-4 h-4 text-base-content/30 group-hover:text-base-content/60 transition-colors" />
            </div>
          </.link>
        <%% end %>
      <%% end %>
    </div>
    """
  end

  defp workspace_href(nil, workspace), do: "/workspaces/#{workspace.id}"
  defp workspace_href(fun, workspace) when is_function(fun, 1), do: fun.(workspace)
end
