defmodule JidoMurmurWeb.Components do
  @moduledoc """
  Unified import module for all jido_murmur_web components.

  ## Usage

  Import all components at once in a LiveView or component module:

      import JidoMurmurWeb.Components

  This makes the following function components available:

    * `chat_message/1` — Single chat message bubble
    * `agent_header/1` — Agent column header bar
    * `message_input/1` — Chat textarea with keyboard shortcuts
    * `streaming_indicator/1` — Agent busy/idle indicator
    * `agent_selector/1` — Add-agent dialog
    * `workspace_list/1` — Workspace navigation list
    * `artifact_panel/1` — Artifact side panel with tabs
    * `artifact_badge/1` — Compact artifact badge
    * `artifact_detail/1` — Full artifact detail view
  """

  defmacro __using__(_opts) do
    quote do
      import JidoMurmurWeb.Components.ChatMessage
      import JidoMurmurWeb.Components.AgentHeader
      import JidoMurmurWeb.Components.MessageInput
      import JidoMurmurWeb.Components.StreamingIndicator
      import JidoMurmurWeb.Components.AgentSelector
      import JidoMurmurWeb.Components.WorkspaceList
      import JidoMurmurWeb.Components.ArtifactPanel
    end
  end
end
