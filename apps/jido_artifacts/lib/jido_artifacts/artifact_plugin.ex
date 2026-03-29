defmodule JidoArtifacts.ArtifactPlugin do
  @moduledoc """
  Jido Plugin that intercepts `artifact.*` signals emitted by tool actions,
  persists artifact data in agent state, and broadcasts updates to the
  LiveView via PubSub.

  The plugin:
  1. Broadcasts the artifact payload as
     `{:artifact_update, session_id, artifact_name, data, mode}`
     on the workspace-scoped PubSub topic.
  2. Overrides routing to the `StoreArtifact` action which merges the
     artifact data into `agent.state.artifacts`, ensuring it survives
     hibernate/thaw and page refresh.
  """

  use Jido.Plugin,
    name: "artifacts",
    state_key: :artifacts,
    actions: [],
    signal_patterns: ["artifact.*"]

  alias JidoArtifacts.Actions.StoreArtifact
  alias JidoArtifacts.Artifact

  require Logger

  @impl Jido.Plugin
  def handle_signal(%{type: "artifact." <> _name, data: data} = signal, context) do
    session_id = context.agent.id
    workspace_id = context.agent.state[:workspace_id]
    topic = Artifact.artifact_topic(workspace_id, session_id)

    {artifact_name, artifact_data, mode, merge_result, scope} = extract_signal_data(data)

    :telemetry.execute(
      [:jido_artifacts, :artifact, :store],
      %{system_time: System.system_time()},
      %{session_id: session_id, artifact_name: artifact_name, mode: mode}
    )

    if scope == :workspace do
      Logger.warning("jido_artifacts: scope :workspace is not yet implemented, treating as :agent")
    end

    # Broadcast the original signal with subject populated
    broadcast_signal =
      if signal.subject do
        signal
      else
        %{signal | subject: "/agents/#{session_id}"}
      end

    Phoenix.PubSub.broadcast(JidoArtifacts.pubsub(), topic, broadcast_signal)

    store_params = build_store_params(artifact_name, artifact_data, mode, merge_result)
    {:ok, {:override, {StoreArtifact, store_params}}}
  end

  defp extract_signal_data(data) do
    {
      data[:name] || data["name"],
      data[:data] || data["data"],
      data[:mode] || data["mode"] || :replace,
      data[:merge_result] || data["merge_result"],
      data[:scope] || data["scope"] || :agent
    }
  end

  defp build_store_params(name, data, mode, merge_result) do
    params = %{artifact_name: name, artifact_data: data, artifact_mode: mode}

    if merge_result != nil or mode == :merge do
      Map.put(params, :merge_result, merge_result)
    else
      params
    end
  end
end
