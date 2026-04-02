defmodule JidoArtifacts.ArtifactPlugin do
  @moduledoc """
  Jido Plugin that intercepts `artifact.*` signals emitted by tool actions,
  persists artifact data in agent state, and broadcasts updates to the
  LiveView via PubSub.

  The plugin:
    1. Broadcasts the canonical `%JidoArtifacts.Envelope{}` update on the
      workspace-scoped PubSub topic.
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
  alias JidoArtifacts.Envelope
  alias JidoArtifacts.SignalPayload
  alias JidoArtifacts.SignalUpdate

  require Logger

  @impl Jido.Plugin
  def handle_signal(%{type: "artifact." <> _name, data: %SignalPayload{} = data} = signal, context) do
    session_id = context.agent.id
    workspace_id = context.agent.state[:workspace_id]
    topic = Artifact.artifact_topic(workspace_id, session_id)
    current_artifacts = context.agent.state[:artifacts] || %{}

    %SignalPayload{
      name: artifact_name,
      payload: artifact_data,
      mode: mode,
      merge_result: merge_result,
      scope: scope
    } = data

    artifact_envelope =
      build_envelope(Map.get(current_artifacts, artifact_name), artifact_data, mode, merge_result, context)

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
      signal
      |> Map.put(:data, SignalUpdate.new!(artifact_name, artifact_envelope, mode: mode, scope: scope))
      |> ensure_subject(session_id)

    Phoenix.PubSub.broadcast(JidoArtifacts.pubsub(), topic, broadcast_signal)

    store_params = build_store_params(artifact_name, artifact_data, mode, merge_result, artifact_envelope)
    {:ok, {:override, {StoreArtifact, store_params}}}
  end

  defp build_store_params(name, data, mode, merge_result, artifact_envelope) do
    params = %{artifact_name: name, artifact_data: data, artifact_mode: mode}

    params =
      if artifact_envelope do
        Map.put(params, :artifact_envelope, artifact_envelope)
      else
        params
      end

    if merge_result != nil or mode == :merge do
      Map.put(params, :merge_result, merge_result)
    else
      params
    end
  end

  defp build_envelope(existing_envelope, artifact_data, mode, merge_result, context) do
    data_to_store =
      case mode do
        :merge -> merge_result
        _replace -> artifact_data
      end

    if is_nil(data_to_store) do
      nil
    else
      Envelope.next(existing_envelope, data_to_store, artifact_source(context))
    end
  end

  defp artifact_source(context) do
    context.agent.state[:__agent_id__] || context.agent.id || "unknown"
  end

  defp ensure_subject(%{subject: nil} = signal, session_id),
    do: %{signal | subject: "/agents/#{session_id}"}

  defp ensure_subject(signal, _session_id), do: signal
end
