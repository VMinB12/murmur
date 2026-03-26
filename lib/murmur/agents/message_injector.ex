defmodule Murmur.Agents.MessageInjector do
  @moduledoc """
  ReAct request transformer that injects team context and pending messages.

  Implements `Jido.AI.Reasoning.ReAct.RequestTransformer` — called before
  every LLM API call within an agent's reasoning loop.

  Two responsibilities:

  1. **Team instructions** — A dynamic system message describing the multi-agent
     workspace, collaboration guidelines, and an up-to-date team roster. Injected
     right after the original system prompt so the LLM always has fresh context
     about who its teammates are.

  2. **Pending messages** — When a message arrives for a busy agent (user input or
     inter-agent "tell"), it is enqueued in `PendingQueue`. This module drains
     the queue and appends the messages so the LLM sees them on the next iteration.
  """

  @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

  alias Murmur.Agents.PendingQueue
  alias Murmur.Agents.TeamInstructions

  @impl true
  def transform_request(request, _state, _config, runtime_context) do
    agent_id = runtime_context[:agent_id]
    workspace_id = runtime_context[:workspace_id]
    sender_name = runtime_context[:sender_name]

    messages =
      request.messages
      |> inject_team_instructions(workspace_id, sender_name)
      |> inject_pending_messages(agent_id)

    if messages == request.messages do
      {:ok, %{}}
    else
      {:ok, %{messages: messages}}
    end
  end

  # Insert the dynamic team-context system message right after the first system
  # prompt so it sits at the top of the conversation alongside the agent's
  # personality/expertise prompt.
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
    case PendingQueue.drain(agent_id) do
      [] ->
        messages

      pending ->
        injected = Enum.map(pending, fn content -> %{role: :user, content: content} end)
        messages ++ injected
    end
  end
end
