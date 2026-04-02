defmodule <%= @app_module %>Web.Components.ArtifactPanel do
  @moduledoc """
  Artifact panel with tab bar and detail view, including built-in
  renderers for common artifact types.
  """

  use Phoenix.Component

  alias JidoArtifacts.Envelope
  import <%= @app_module %>Web.CoreComponents, only: [icon: 1]

  alias __MODULE__.Generic
  alias __MODULE__.PaperList
  alias __MODULE__.PdfViewer

  @default_renderers %%{
    "papers" => PaperList,
    "displayed_paper" => PdfViewer
  }

  defp extract_data(%Envelope{data: inner}), do: inner
  defp empty_artifact?(nil), do: true
  defp empty_artifact?(%Envelope{data: data}), do: data == nil or data == [] or data == %%{}

  attr :name, :string, required: true
  attr :data, :any, required: true
  attr :session_id, :string, required: true
  attr :active?, :boolean, default: false
  attr :renderers, :map, default: %%{}

  def artifact_badge(assigns) do
    renderer = Map.get(assigns.renderers, assigns.name) || Map.get(@default_renderers, assigns.name)
    assigns =
      assigns
      |> assign(:renderer, renderer)
      |> update(:data, &extract_data/1)

    ~H"""
    <%%= if @renderer do %>
      <@renderer badge name={@name} data={@data} session_id={@session_id} active?={@active?} />
    <%% else %>
      <Generic.badge name={@name} data={@data} session_id={@session_id} active?={@active?} />
    <%% end %>
    """
  end

  attr :name, :string, required: true
  attr :data, :any, required: true
  attr :session_id, :string, required: true
  attr :renderers, :map, default: %%{}

  def artifact_detail(assigns) do
    renderer = Map.get(assigns.renderers, assigns.name) || Map.get(@default_renderers, assigns.name)
    assigns =
      assigns
      |> assign(:renderer, renderer)
      |> update(:data, &extract_data/1)

    ~H"""
    <%%= if @renderer do %>
      <@renderer detail name={@name} data={@data} session_id={@session_id} />
    <%% else %>
      <Generic.detail name={@name} data={@data} session_id={@session_id} />
    <%% end %>
    """
  end

  attr :artifacts, :map, required: true
  attr :active_artifact, :any, required: true
  attr :agent_sessions, :list, required: true
  attr :renderers, :map, default: %%{}

  def artifact_panel(assigns) do
    session_index = Map.new(assigns.agent_sessions, &{&1.id, &1})

    tabs =
      assigns.artifacts
      |> Enum.flat_map(fn {session_id, artifacts_map} ->
        session = Map.get(session_index, session_id)
        agent_name = if session, do: session.display_name, else: "agent"

        artifacts_map
        |> Enum.reject(fn {_name, data} -> empty_artifact?(data) end)
        |> Enum.map(fn {name, _data} ->
          %%{session_id: session_id, agent_name: agent_name, name: name}
        end)
      end)
      |> Enum.sort_by(&{&1.agent_name, &1.name})

    active = assigns.active_artifact
    active_data =
      if active, do: get_in(assigns.artifacts, [active.session_id, active.name])

    assigns =
      assigns
      |> assign(:tabs, tabs)
      |> assign(:active_data, active_data)

    ~H"""
    <div class="flex flex-col h-full border-l border-base-300/50 bg-base-100">
      <div class="flex items-center gap-1 px-2 py-1.5 border-b border-base-300/50 overflow-x-auto shrink-0 bg-base-200/20">
        <%%= if @tabs == [] do %>
          <span class="text-[11px] text-base-content/30 px-1">No artifacts yet</span>
        <%% else %>
          <%%= for tab <- @tabs do %>
            <%% active? = @active_artifact && @active_artifact.session_id == tab.session_id && @active_artifact.name == tab.name %>
            <button
              phx-click="open_artifact"
              phx-value-session-id={tab.session_id}
              phx-value-name={tab.name}
              class={[
                "inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md text-[11px] font-medium transition-colors whitespace-nowrap",
                if(active?, do: "bg-primary/15 text-primary", else: "text-base-content/50 hover:bg-base-200/60 hover:text-base-content/70")
              ]}
            >
              <span class="text-base-content/40">{tab.agent_name}</span>
              <span>/</span>
              <span>{tab.name}</span>
            </button>
          <%% end %>
        <%% end %>
      </div>

      <div class="flex-1 min-h-0">
        <%%= if @active_artifact && @active_data do %>
          <.artifact_detail name={@active_artifact.name} data={@active_data} session_id={@active_artifact.session_id} renderers={@renderers} />
        <%% else %>
          <div class="flex flex-col items-center justify-center h-full text-base-content/30 gap-3 px-6">
            <.icon name="hero-square-3-stack-3d" class="w-10 h-10 opacity-30" />
            <div class="text-center">
              <p class="text-sm font-medium">Artifacts</p>
              <p class="text-xs mt-1 text-base-content/20">Tool results and data will appear here as agents work.</p>
            </div>
          </div>
        <%% end %>
      </div>
    </div>
    """
  end
end
