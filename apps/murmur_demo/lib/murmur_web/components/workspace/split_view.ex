defmodule MurmurWeb.Components.Workspace.SplitView do
  @moduledoc false
  use MurmurWeb, :html

  import JidoMurmurWeb.Components.AgentHeader
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

  def split_view(assigns) do
    ~H"""
    <div class="flex-1 flex min-h-0">
      <div class="flex-1 flex overflow-x-auto min-h-0">
        <%= for session <- @agent_sessions do %>
          <% colors = Catalog.agent_color(session.agent_profile_id, session.display_name) %>
          <% stream = Map.get(@streaming, session.id, empty_stream()) %>
          <% messages = Map.get(@messages, session.id, []) %>
          <% artifacts = visible_artifacts(Map.get(@artifacts, session.id, %{})) %>

          <section class="flex flex-col flex-1 min-w-[300px] border-r border-base-300/50 last:border-r-0 agent-column-enter transition-all duration-200">
            <.agent_header
              session={session}
              color={colors}
              status={Map.get(@agent_statuses, session.id, :idle)}
            />

            <div
              id={"messages-#{session.id}"}
              phx-hook="AutoScroll"
              class="flex-1 overflow-y-auto px-3 py-3 space-y-3"
            >
              <%= if messages == [] and empty_stream?(stream) do %>
                <div class="flex items-center justify-center h-full text-base-content/40 text-sm">
                  Send a message to start chatting
                </div>
              <% end %>

              <%= for message <- messages do %>
                <.chat_message
                  message={message}
                  color={message_color(message)}
                  markdown_renderer={@markdown_renderer}
                />
              <% end %>

              <.chat_stream stream={stream} color={colors} />
            </div>

            <%= if artifacts != [] do %>
              <div class="flex items-center gap-1.5 px-3 py-1.5 border-t border-base-300/50 overflow-x-auto">
                <%= for {name, data} <- artifacts do %>
                  <.artifact_badge
                    name={name}
                    data={data}
                    session_id={session.id}
                    active?={
                      @active_artifact != nil and @active_artifact.session_id == session.id and
                        @active_artifact.name == name
                    }
                  />
                <% end %>
              </div>
            <% end %>

            <.message_input
              id={"msg-form-#{session.id}"}
              session_id={session.id}
              input_id={"chat-input-#{session.id}"}
            />
          </section>
        <% end %>
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

  defp visible_artifacts(artifacts) do
    artifacts
    |> Enum.filter(fn {_name, data} -> WorkspaceState.artifact_present?(data) end)
  end

  defp empty_stream, do: %{content: "", thinking: "", tool_calls: [], usage: nil}

  defp empty_stream?(stream) do
    stream.content == "" and stream.thinking == "" and stream.tool_calls == []
  end

  defp message_color(%{role: "user", sender_name: sender_name}) when sender_name not in [nil, "You"] do
    Catalog.agent_color(nil, sender_name)
  end

  defp message_color(_message), do: nil
end
