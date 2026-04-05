defmodule MurmurWeb.Components.Workspace.UnifiedView do
  @moduledoc false
  use MurmurWeb, :html

  alias JidoMurmur.DisplayMessage
  import JidoMurmurWeb.Components.ChatMessage
  import JidoMurmurWeb.Components.ChatStream
  import JidoMurmurWeb.Components.MessageInput

  alias MurmurWeb.Live.WorkspaceState

  attr :agent_sessions, :list, required: true
  attr :agent_statuses, :map, required: true
  attr :messages, :map, required: true
  attr :streaming, :map, required: true
  attr :artifacts, :map, required: true
  attr :active_artifact, :any, required: true
  attr :show_task_board, :boolean, required: true
  attr :tasks, :list, required: true
  attr :task_form, :any, required: true
  attr :markdown_renderer, :any, required: true

  def unified_view(assigns) do
    assigns = assign(assigns, :timeline, WorkspaceState.unified_timeline(assigns.messages, assigns.agent_sessions))

    ~H"""
    <div class="flex-1 flex min-h-0">
      <aside class="w-52 shrink-0 border-r border-base-300/50 flex flex-col bg-base-100/80">
        <div class="px-3 py-2 border-b border-base-300/50">
          <span class="text-[10px] uppercase tracking-wider text-base-content/40">Agents</span>
        </div>
        <div class="flex-1 overflow-y-auto py-2 space-y-1">
          <%= for session <- @agent_sessions do %>
            <% colors = Catalog.agent_color(session.agent_profile_id, session.display_name) %>
            <div class="mx-2 rounded-box px-3 py-2 hover:bg-base-200/40 transition-colors group">
              <div class="flex items-center justify-between gap-2">
                <div class="flex items-center gap-2 min-w-0">
                  <div class={[
                    "w-2.5 h-2.5 rounded-full shrink-0",
                    colors.dot
                  ]}></div>
                  <span class={[
                    "text-sm font-medium truncate",
                    colors.text
                  ]}>{session.display_name}</span>
                </div>
                <div class="flex items-center gap-1 shrink-0">
                  <%= if Map.get(@agent_statuses, session.id) == :busy do %>
                    <span class="loading loading-dots loading-xs text-warning"></span>
                  <% end %>
                  <button
                    phx-click="remove_agent"
                    phx-value-session-id={session.id}
                    data-confirm="Remove this agent?"
                    class="btn btn-ghost btn-xs opacity-0 group-hover:opacity-60 hover:!opacity-100"
                  >
                    <.icon name="hero-x-mark" class="w-3 h-3" />
                  </button>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </aside>

      <div class="flex-1 flex flex-col min-w-0">
        <div id="unified-messages" phx-hook="AutoScroll" class="flex-1 overflow-y-auto px-4 py-4 space-y-4">
          <%= if @timeline == [] and Enum.all?(@streaming, fn {_id, stream} -> empty_stream?(stream) end) do %>
            <div class="flex items-center justify-center h-full text-base-content/40 text-sm">
              Send a message to start chatting. Use @name to target a specific agent.
            </div>
          <% end %>

          <%= for message <- @timeline do %>
            <%= if message.role == "user" do %>
              <div id={"unified-msg-#{message.id}"} class="ml-auto max-w-[72%]">
                <.chat_message
                  message={message}
                  color={message_color(message)}
                  markdown_renderer={@markdown_renderer}
                />
              </div>
            <% else %>
              <div id={"unified-msg-#{message.id}"} class="flex gap-3 items-start">
                <div class="avatar placeholder shrink-0 pt-1">
                  <div class={[
                    "w-9 rounded-full text-white text-xs font-semibold",
                    message.agent_color.dot
                  ]}>
                    <span>{String.first(message.agent_name || "?")}</span>
                  </div>
                </div>
                <div class="min-w-0 max-w-[72%] flex-1">
                  <.chat_message
                    message={message}
                    color={message_color(message)}
                    markdown_renderer={@markdown_renderer}
                  />
                </div>
              </div>
            <% end %>
          <% end %>

          <%= for session <- @agent_sessions do %>
            <% stream = Map.get(@streaming, session.id, empty_stream()) %>
            <%= if not empty_stream?(stream) do %>
              <% colors = Catalog.agent_color(session.agent_profile_id, session.display_name) %>
              <div class="flex gap-3 items-start">
                <div class="avatar placeholder shrink-0 pt-1">
                  <div class={[
                    "w-9 rounded-full text-white text-xs font-semibold",
                    colors.dot
                  ]}>
                    <span>{String.first(session.display_name || "?")}</span>
                  </div>
                </div>
                <div class="min-w-0 max-w-[72%] flex-1">
                  <.chat_stream
                    stream={stream}
                    color={Map.put(colors, :label, session.display_name)}
                  />
                </div>
              </div>
            <% end %>
          <% end %>
        </div>

        <%= if visible_artifacts?(@artifacts) do %>
          <div class="flex items-center gap-1.5 px-4 py-1.5 border-t border-base-300/50 overflow-x-auto">
            <%= for {session_id, name, data} <- visible_artifacts(@artifacts) do %>
              <.artifact_badge
                name={name}
                data={data}
                session_id={session_id}
                active?={
                  @active_artifact != nil and @active_artifact.session_id == session_id and
                    @active_artifact.name == name
                }
              />
            <% end %>
          </div>
        <% end %>

        <.message_input
          id="unified-msg-form"
          on_submit="send_unified_message"
          input_id="unified-chat-input"
          container_class="px-4 py-3 border-t border-base-300"
          placeholder={unified_placeholder(@agent_sessions)}
        />
      </div>

      <div class="w-[480px] shrink-0">
        <%= if @show_task_board do %>
          <TaskBoard.board
            tasks={@tasks}
            agent_sessions={@agent_sessions}
            task_form={@task_form}
          />
        <% else %>
          <.artifact_panel
            artifacts={@artifacts}
            active_artifact={@active_artifact}
            agent_sessions={@agent_sessions}
          />
        <% end %>
      </div>
    </div>
    """
  end

  defp empty_stream?(stream) do
    stream.content == "" and stream.thinking == "" and stream.tool_calls == []
  end

  defp empty_stream, do: %{content: "", thinking: "", tool_calls: [], usage: nil}

  defp visible_artifacts?(artifacts), do: visible_artifacts(artifacts) != []

  defp visible_artifacts(artifacts) do
    artifacts
    |> Enum.flat_map(fn {session_id, session_artifacts} ->
      session_artifacts
      |> Enum.filter(fn {_name, data} -> WorkspaceState.artifact_present?(data) end)
      |> Enum.map(fn {name, data} -> {session_id, name, data} end)
    end)
  end

  defp unified_placeholder(agent_sessions) do
    first_session = List.first(agent_sessions)
    first_name = if first_session, do: first_session.display_name, else: "agent"
    "@#{first_name} message... or just type to send to the first agent"
  end

  defp message_color(%{role: "assistant", agent_color: agent_color}), do: agent_color

  defp message_color(message) do
    if DisplayMessage.external_user_message?(message) do
      Catalog.agent_color(nil, DisplayMessage.label(message))
    else
      nil
    end
  end
end
