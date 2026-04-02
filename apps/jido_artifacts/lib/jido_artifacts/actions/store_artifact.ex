defmodule JidoArtifacts.Actions.StoreArtifact do
  @moduledoc """
  Action that merges artifact data into the agent's `:artifacts` state key.

  Used by the ArtifactPlugin as an override action so that artifact data
  is persisted in the agent's state (and thus survives hibernate/thaw).

  Supports two modes:
  - `:replace` — overwrites the named artifact entirely
  - `:append`  — appends new items to an existing list artifact
  """

  alias JidoArtifacts.Envelope

  use Jido.Action,
    name: "store_artifact",
    description: "Stores artifact data in agent state",
    schema: [
      artifact_name: [type: :string, required: true, doc: "Name of the artifact"],
      artifact_data: [type: :any, required: true, doc: "The artifact payload"],
      artifact_mode: [type: :atom, default: :replace, doc: ":replace or :merge"],
      merge_result: [type: :any, doc: "Pre-computed merge result (when mode is :merge)"],
      artifact_envelope: [type: :any, doc: "Canonical envelope for the artifact update"]
    ]

  def run(%{artifact_name: name, artifact_mode: mode} = params, ctx) do
    current_artifacts = get_in(ctx, [:state, :artifacts]) || %{}
    existing_envelope = Map.get(current_artifacts, name)

    data_to_store =
      case mode do
        :merge ->
          params.merge_result

        _replace ->
          params.artifact_data
      end

    if data_to_store == nil do
      {:ok, %{artifacts: Map.delete(current_artifacts, name)}}
    else
      envelope =
        case Map.get(params, :artifact_envelope) do
          %Envelope{} = artifact_envelope ->
            artifact_envelope

          nil ->
            Envelope.next(existing_envelope, data_to_store, artifact_source(ctx))
        end

      {:ok, %{artifacts: Map.put(current_artifacts, name, envelope)}}
    end
  end

  defp artifact_source(ctx) do
    get_in(ctx, [:state, :__agent_id__]) || get_in(ctx, [:agent, :id]) || "unknown"
  end
end
