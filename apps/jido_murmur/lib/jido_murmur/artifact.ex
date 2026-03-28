defmodule JidoMurmur.Artifact do
  @moduledoc """
  Helpers for creating artifact signals from tool actions.

  An artifact is structured data produced by a tool that should be displayed
  to the user outside the normal chat message flow. Examples include search
  results, query result tables, and documents.

  ## Usage in a tool action

      def run(params, ctx) do
        papers = ArxivClient.search(params.query)
        llm_summary = papers |> Enum.take(5) |> Enum.map_join("\\n", & &1.title)

        {:ok, %{result: llm_summary},
          JidoMurmur.Artifact.emit(ctx, "papers", papers, mode: :append)}
      end

  ## Modes

  - `:replace` — the new data replaces the current artifact entirely (default)
  - `:append`  — the new data is appended to the existing artifact list
  """

  alias Jido.Agent.Directive

  @type mode :: :replace | :append

  @doc """
  Creates an `Emit` directive that broadcasts an artifact update.

  The directive emits a signal of type `"artifact.<name>"` carrying the
  artifact payload. The `ArtifactPlugin` intercepts this signal and
  forwards it to the LiveView via PubSub.

  ## Options

    * `:mode` — `:replace` (default) or `:append`
  """
  @spec emit(map(), String.t(), term(), keyword()) :: Directive.Emit.t()
  def emit(_ctx, name, data, opts \\ []) do
    mode = Keyword.get(opts, :mode, :replace)

    signal =
      Jido.Signal.new!(
        "artifact.#{name}",
        %{name: name, data: data, mode: mode},
        source: "/artifact/#{name}"
      )

    %Directive.Emit{signal: signal}
  end

  @doc "PubSub topic for artifact updates for the given session."
  def artifact_topic(session_id), do: "agent_artifacts:#{session_id}"
end
