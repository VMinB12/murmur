defmodule MurmurWeb.Components.Artifacts do
  @moduledoc """
  Demo integration layer for artifact rendering.

  Delegates the generic artifact panel UI to `jido_murmur_web` while injecting
  the demo app's renderer registry for SQL and arXiv-specific artifact types.
  """

  use Phoenix.Component

  alias JidoMurmurWeb.Components.ArtifactPanel, as: SharedArtifactPanel
  alias MurmurWeb.Artifacts.Registry

  @doc "Renders a compact clickable badge for an artifact in the chat column."
  attr :name, :string, required: true
  attr :data, :any, required: true
  attr :session_id, :string, required: true
  attr :active?, :boolean, default: false
  attr :renderers, :map, default: %{}

  def artifact_badge(assigns) do
    SharedArtifactPanel.artifact_badge(%{assigns | renderers: Registry.merge(assigns.renderers)})
  end

  @doc "Renders the full artifact detail view for the side panel."
  attr :name, :string, required: true
  attr :data, :any, required: true
  attr :session_id, :string, required: true
  attr :renderers, :map, default: %{}

  def artifact_detail(assigns) do
    SharedArtifactPanel.artifact_detail(%{assigns | renderers: Registry.merge(assigns.renderers)})
  end

  @doc """
  The full artifact side panel with tab bar and detail view.

  Renders a tab for each non-empty artifact across all sessions,
  and the detail view for the currently active artifact.
  """
  attr :artifacts, :map, required: true
  attr :active_artifact, :any, required: true
  attr :agent_sessions, :list, required: true
  attr :renderers, :map, default: %{}

  def artifact_panel(assigns) do
    SharedArtifactPanel.artifact_panel(%{assigns | renderers: Registry.merge(assigns.renderers)})
  end
end
