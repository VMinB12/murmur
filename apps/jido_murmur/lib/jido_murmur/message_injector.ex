defmodule JidoMurmur.MessageInjector do
  @moduledoc """
  ReAct request transformer that injects team context and pending messages.

  Implements `Jido.AI.Reasoning.ReAct.RequestTransformer` — called before
  every LLM API call within an agent's reasoning loop.

  Two responsibilities:

  1. **Team instructions** — A dynamic system message describing the multi-agent
     workspace, collaboration guidelines, and an up-to-date team roster.
  2. **Pending messages** — When a message arrives for a busy agent, it is
     enqueued in `PendingQueue`. This module drains the queue and appends
     the messages so the LLM sees them on the next iteration.
  """

  @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

  alias JidoMurmur.Observability
  alias JidoMurmur.PendingQueue
  alias JidoMurmur.TeamInstructions

  @impl true
  def transform_request(request, state, _config, runtime_context) do
    agent_id = runtime_context[:agent_id]
    workspace_id = runtime_context[:workspace_id]
    sender_name = runtime_context[:sender_name]

    messages =
      request.messages
      |> inject_team_instructions(workspace_id, sender_name)
      |> inject_pending_messages(agent_id)

    record_prepared_input(state, messages)

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

  defp inject_pending_messages(messages, nil), do: messages

  defp inject_pending_messages(messages, agent_id) do
    case PendingQueue.drain_envelopes(agent_id) do
      [] ->
        messages

      pending ->
        Observability.record_injected_messages(agent_id, pending)
        injected = Enum.map(pending, fn envelope -> %{role: :user, content: envelope.content} end)
        messages ++ injected
    end
  end

  defp record_prepared_input(%{llm_call_id: call_id}, messages) when is_binary(call_id) and is_list(messages) do
    Observability.record_prepared_llm_input(call_id, messages)
  end

  defp record_prepared_input(_state, _messages), do: :ok
end
