defmodule JidoMurmur.MessageInjector do
  @moduledoc """
  ReAct request transformer that injects Murmur team context.

  Implements `Jido.AI.Reasoning.ReAct.RequestTransformer` — called before
  every LLM API call within an agent's reasoning loop.

  Its only responsibility is adding a dynamic system message that describes
  the multi-agent workspace, collaboration guidelines, and current team roster.
  """

  @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

  alias JidoMurmur.Observability
  alias JidoMurmur.TeamInstructions

  @impl true
  def transform_request(request, state, _config, runtime_context) do
    workspace_id = runtime_context[:workspace_id]
    sender_name = runtime_context[:sender_name]

    messages =
      request.messages
      |> inject_team_instructions(workspace_id, sender_name)

    Observability.record_prepared_llm_input(state, messages)

    if messages == request.messages do
      {:ok, %{}}
    else
      {:ok, %{messages: messages}}
    end
  end

  defp inject_team_instructions(messages, nil, _sender_name), do: messages
  defp inject_team_instructions(messages, _workspace_id, nil), do: messages

  defp inject_team_instructions(messages, workspace_id, sender_name) do
    team_text = TeamInstructions.build(workspace_id, sender_name)

    case messages do
      [%{role: :system, content: existing} = sys | rest] ->
        [%{sys | content: existing <> "\n\n" <> team_text} | rest]

      other ->
        [%{role: :system, content: team_text} | other]
    end
  end
end
