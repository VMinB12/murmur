defmodule JidoArtifacts.Artifact do
  @moduledoc """
  Helpers for creating artifact signals from tool actions.

  An artifact is structured data produced by a tool that should be displayed
  to the user outside the normal chat message flow. Examples include search
  results, query result tables, and documents.

  ## Usage in a tool action

      alias JidoArtifacts.{Artifact, Merge}

      def run(params, ctx) do
        papers = ArxivClient.search(params.query)
        llm_summary = papers |> Enum.take(5) |> Enum.map_join("\\n", & &1.title)

        {:ok, %{result: llm_summary},
          Artifact.emit(ctx, "papers", papers, merge: &Merge.append/2)}
      end

  ## Merge Callbacks

  When `:merge` is provided, the function is applied eagerly at emit-time
  using the existing artifact data from the action context. The merged result
  is included in the signal as `merge_result`.

  When `:merge` is omitted, the signal carries `mode: :replace`.
  """

  alias Jido.Agent.Directive
  alias JidoArtifacts.Envelope
  alias JidoArtifacts.SignalPayload

  @doc """
  Creates an `Emit` directive that broadcasts an artifact update.

  The directive emits a signal of type `"artifact.<name>"` carrying the
  artifact payload. The `ArtifactPlugin` intercepts this signal and
  forwards it to the LiveView via PubSub.

  ## Options

    * `:merge` — a 2-arity function `(existing, new) -> merged`.
      When provided, the merge is computed eagerly and included as `merge_result`.
    * `:scope` — `:agent` (default) or `:workspace` (reserved for future use)
  """
  @spec emit(map(), String.t(), term(), keyword()) :: Directive.Emit.t()
  def emit(ctx, name, data, opts \\ []) do
    merge_fn = Keyword.get(opts, :merge)
    scope = Keyword.get(opts, :scope, :agent)

    signal_data =
      if merge_fn do
        existing = existing_artifact_payload(get_in(ctx, [:state, :artifacts, name]))
        merge_result = merge_fn.(existing, data)
        SignalPayload.new!(name, data, mode: :merge, merge_result: merge_result, scope: scope)
      else
        SignalPayload.new!(name, data, scope: scope)
      end

    agent_id = get_in(ctx, [:state, :__agent_id__])

    subject =
      if agent_id do
        "/agents/#{agent_id}"
      end

    signal_opts =
      [source: "/jido_artifacts/#{name}"]
      |> then(fn opts -> if subject, do: Keyword.put(opts, :subject, subject), else: opts end)

    signal = Jido.Signal.new!("artifact.#{name}", signal_data, signal_opts)

    %Directive.Emit{signal: signal}
  end

  @doc "PubSub topic for artifact updates for the given session."
  @spec artifact_topic(String.t(), String.t()) :: String.t()
  def artifact_topic(workspace_id, session_id),
    do: "workspace:#{workspace_id}:agent:#{session_id}:artifacts"

  defp existing_artifact_payload(nil), do: nil
  defp existing_artifact_payload(%Envelope{} = envelope), do: Envelope.data(envelope)
end
