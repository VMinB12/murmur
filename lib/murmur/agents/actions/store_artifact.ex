defmodule Murmur.Agents.Actions.StoreArtifact do
  @moduledoc """
  Action that merges artifact data into the agent's `:artifacts` state key.

  Used by the ArtifactPlugin as an override action so that artifact data
  is persisted in the agent's state (and thus survives hibernate/thaw).

  Supports two modes:
  - `:replace` — overwrites the named artifact entirely
  - `:append`  — appends new items to an existing list artifact
  """

  use Jido.Action,
    name: "store_artifact",
    description: "Stores artifact data in agent state",
    schema: [
      artifact_name: [type: :string, required: true, doc: "Name of the artifact"],
      artifact_data: [type: :any, required: true, doc: "The artifact payload"],
      artifact_mode: [type: :atom, default: :replace, doc: ":replace or :append"]
    ]

  def run(%{artifact_name: name, artifact_data: data, artifact_mode: mode}, ctx) do
    current_artifacts = get_in(ctx, [:state, :artifacts]) || %{}

    updated =
      case mode do
        :append ->
          existing = Map.get(current_artifacts, name, [])
          Map.put(current_artifacts, name, existing ++ List.wrap(data))

        _replace ->
          Map.put(current_artifacts, name, data)
      end

    {:ok, %{artifacts: updated}}
  end
end
