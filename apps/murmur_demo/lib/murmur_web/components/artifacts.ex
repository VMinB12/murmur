defmodule MurmurWeb.Components.Artifacts do
  @moduledoc """
  Dispatcher for artifact rendering components.

  Delegates to type-specific renderers based on the artifact name.
  To add a new artifact type, create a module under
  `MurmurWeb.Components.Artifacts.*` with `badge/1` and `detail/1`,
  then add a clause here.
  """

  use Phoenix.Component

  import MurmurWeb.CoreComponents, only: [icon: 1]

  alias MurmurWeb.Components.Artifacts.Generic
  alias MurmurWeb.Components.Artifacts.PaperList
  alias MurmurWeb.Components.Artifacts.PdfViewer
  alias MurmurWeb.Components.Artifacts.SqlResults

  # Artifact data is stored in an envelope %{data: ..., version: ..., ...}.
  # Unwrap it before passing to renderers.
  defp unwrap_envelope(%{data: inner}), do: inner
  defp unwrap_envelope(data), do: data

  # --- Badge dispatcher ---

  @doc "Renders a compact clickable badge for an artifact in the chat column."
  attr :name, :string, required: true
  attr :data, :any, required: true
  attr :session_id, :string, required: true
  attr :active?, :boolean, default: false

  def artifact_badge(%{name: "papers"} = assigns) do
    assigns = update(assigns, :data, &unwrap_envelope/1)

    ~H"""
    <PaperList.badge data={@data} session_id={@session_id} active?={@active?} />
    """
  end

  def artifact_badge(%{name: "displayed_paper"} = assigns) do
    assigns = update(assigns, :data, &unwrap_envelope/1)

    ~H"""
    <PdfViewer.badge data={@data} session_id={@session_id} active?={@active?} />
    """
  end

  def artifact_badge(%{name: "sql_results"} = assigns) do
    assigns = update(assigns, :data, &unwrap_envelope/1)

    ~H"""
    <SqlResults.badge data={@data} session_id={@session_id} active?={@active?} />
    """
  end

  def artifact_badge(assigns) do
    assigns = update(assigns, :data, &unwrap_envelope/1)

    ~H"""
    <Generic.badge name={@name} data={@data} session_id={@session_id} active?={@active?} />
    """
  end

  # --- Detail dispatcher ---

  @doc "Renders the full artifact detail view for the side panel."
  attr :name, :string, required: true
  attr :data, :any, required: true
  attr :session_id, :string, required: true

  def artifact_detail(%{name: "papers"} = assigns) do
    ~H"""
    <PaperList.detail data={@data} session_id={@session_id} />
    """
  end

  def artifact_detail(%{name: "displayed_paper"} = assigns) do
    ~H"""
    <PdfViewer.detail data={@data} session_id={@session_id} />
    """
  end

  def artifact_detail(%{name: "sql_results"} = assigns) do
    ~H"""
    <SqlResults.detail data={@data} session_id={@session_id} />
    """
  end

  def artifact_detail(assigns) do
    ~H"""
    <Generic.detail name={@name} data={@data} session_id={@session_id} />
    """
  end

  # --- Artifact panel ---

  @doc """
  The full artifact side panel with tab bar and detail view.

  Renders a tab for each non-empty artifact across all sessions,
  and the detail view for the currently active artifact.
  """
  attr :artifacts, :map, required: true
  attr :active_artifact, :any, required: true
  attr :agent_sessions, :list, required: true

  def artifact_panel(assigns) do
    # Build flat list of {session_id, agent_name, artifact_name} tuples for the tab bar
    session_index = Map.new(assigns.agent_sessions, &{&1.id, &1})

    tabs =
      assigns.artifacts
      |> Enum.flat_map(fn {session_id, artifacts_map} ->
        session = Map.get(session_index, session_id)
        agent_name = if session, do: session.display_name, else: "agent"

        artifacts_map
        |> Enum.reject(fn {_name, data} -> data == nil or data == [] or data == %{} end)
        |> Enum.map(fn {name, _data} ->
          %{session_id: session_id, agent_name: agent_name, name: name}
        end)
      end)
      |> Enum.sort_by(&{&1.agent_name, &1.name})

    active = assigns.active_artifact

    active_data =
      if active do
        assigns.artifacts
        |> get_in([active.session_id, active.name])
        |> unwrap_envelope()
      end

    assigns =
      assigns
      |> assign(:tabs, tabs)
      |> assign(:active_data, active_data)

    ~H"""
    <div class="flex flex-col h-full border-l border-base-300/50 bg-base-100">
      <%!-- Tab bar --%>
      <div class="flex items-center gap-1 px-2 py-1.5 border-b border-base-300/50 overflow-x-auto shrink-0 bg-base-200/20">
        <%= if @tabs == [] do %>
          <span class="text-[11px] text-base-content/30 px-1">No artifacts yet</span>
        <% else %>
          <%= for tab <- @tabs do %>
            <% active? =
              @active_artifact && @active_artifact.session_id == tab.session_id &&
                @active_artifact.name == tab.name %>
            <button
              phx-click="open_artifact"
              phx-value-session-id={tab.session_id}
              phx-value-name={tab.name}
              class={[
                "inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md text-[11px] font-medium transition-colors whitespace-nowrap",
                if(active?,
                  do: "bg-primary/15 text-primary",
                  else: "text-base-content/50 hover:bg-base-200/60 hover:text-base-content/70"
                )
              ]}
            >
              <span class="text-base-content/40">{tab.agent_name}</span>
              <span>/</span>
              <span>{tab.name}</span>
            </button>
          <% end %>
        <% end %>
      </div>

      <%!-- Detail view --%>
      <div class="flex-1 min-h-0">
        <%= if @active_artifact && @active_data do %>
          <.artifact_detail
            name={@active_artifact.name}
            data={@active_data}
            session_id={@active_artifact.session_id}
          />
        <% else %>
          <div class="flex flex-col items-center justify-center h-full text-base-content/30 gap-3 px-6">
            <.icon name="hero-square-3-stack-3d" class="w-10 h-10 opacity-30" />
            <div class="text-center">
              <p class="text-sm font-medium">Artifacts</p>
              <p class="text-xs mt-1 text-base-content/20">
                Tool results and data will appear here as agents work.
              </p>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
