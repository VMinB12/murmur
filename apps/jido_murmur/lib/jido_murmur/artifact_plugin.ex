defmodule JidoMurmur.ArtifactPlugin do
  @moduledoc """
  Jido Plugin that intercepts `artifact.*` signals emitted by tool actions,
  persists artifact data in agent state, and broadcasts updates to the
  LiveView via PubSub.

  The plugin:
  1. Broadcasts the artifact payload as
     `{:artifact_update, session_id, artifact_name, data, mode}`
     on the PubSub topic `"agent_artifacts:<session_id>"`.
  2. Overrides routing to the `StoreArtifact` action which merges the
     artifact data into `agent.state.artifacts`, ensuring it survives
     hibernate/thaw and page refresh.
  """

  use Jido.Plugin,
    name: "artifacts",
    state_key: :artifacts,
    actions: [],
    signal_patterns: ["artifact.*"]

  alias JidoMurmur.Actions.StoreArtifact
  alias JidoMurmur.Artifact

  @impl Jido.Plugin
  def handle_signal(%{type: "artifact." <> _name, data: data} = _signal, context) do
    session_id = context.agent.id
    topic = Artifact.artifact_topic(session_id)

    artifact_name = data[:name] || data["name"]
    artifact_data = data[:data] || data["data"]
    mode = data[:mode] || data["mode"] || :replace

    :telemetry.execute(
      [:jido_murmur, :artifact, :store],
      %{system_time: System.system_time()},
      %{session_id: session_id, artifact_name: artifact_name, mode: mode}
    )

    Phoenix.PubSub.broadcast(
      JidoMurmur.pubsub(),
      topic,
      {:artifact_update, session_id, artifact_name, artifact_data, mode}
    )

    {:ok,
     {:override, {StoreArtifact, %{artifact_name: artifact_name, artifact_data: artifact_data, artifact_mode: mode}}}}
  end
end
