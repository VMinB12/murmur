defmodule Murmur.Agents.ArtifactPlugin do
  @moduledoc """
  Jido Plugin that intercepts `artifact.*` signals emitted by tool actions,
  persists artifact data in agent state, and broadcasts updates to the
  LiveView via PubSub.

  Tool actions emit artifact signals through `Murmur.Agents.Artifact.emit/4`,
  which returns an `Emit` directive. When the AgentServer drains that directive,
  the signal flows through this plugin's `handle_signal/2` before reaching the
  router.

  The plugin:
  1. Broadcasts the artifact payload as
     `{:artifact_update, session_id, artifact_name, data, mode}`
     on the PubSub topic `"agent_artifacts:<session_id>"`.
  2. Overrides routing to the `StoreArtifact` action which merges the
     artifact data into `agent.state.artifacts`, ensuring it survives
     hibernate/thaw and page refresh.

  ## Signal contract

  Artifact signals have the type `"artifact.<name>"` and carry:

      %{name: "papers", data: [...], mode: :append | :replace}

  The LiveView maintains an `@artifacts` assign (map of session_id to a map of
  artifact_name to artifact data) and updates it based on the mode.
  """

  use Jido.Plugin,
    name: "artifacts",
    state_key: :artifacts,
    actions: [],
    signal_patterns: ["artifact.*"]

  alias Murmur.Agents.Actions.StoreArtifact
  alias Murmur.Agents.Artifact

  @impl Jido.Plugin
  def handle_signal(%{type: "artifact." <> _name, data: data} = _signal, context) do
    session_id = context.agent.id
    topic = Artifact.artifact_topic(session_id)

    artifact_name = data[:name] || data["name"]
    artifact_data = data[:data] || data["data"]
    mode = data[:mode] || data["mode"] || :replace

    Phoenix.PubSub.broadcast(
      Murmur.PubSub,
      topic,
      {:artifact_update, session_id, artifact_name, artifact_data, mode}
    )

    # Override routing to StoreArtifact so the data is persisted in agent state
    {:ok,
     {:override, {StoreArtifact, %{artifact_name: artifact_name, artifact_data: artifact_data, artifact_mode: mode}}}}
  end
end
