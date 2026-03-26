defmodule Murmur.Agents.MessageInjector do
  @moduledoc """
  ReAct request transformer that injects pending messages mid-turn.

  Implements `Jido.AI.Reasoning.ReAct.RequestTransformer` — called before
  every LLM API call within an agent's reasoning loop.

  When a message arrives for a busy agent (user input or inter-agent
  "tell"), it is enqueued in `PendingQueue`. This module drains the
  queue and appends the messages to the conversation history so the
  LLM sees them on the very next iteration.
  """

  @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

  alias Murmur.Agents.PendingQueue

  @impl true
  def transform_request(request, _state, _config, runtime_context) do
    agent_id = runtime_context[:agent_id]

    case PendingQueue.drain(agent_id) do
      [] ->
        {:ok, %{}}

      pending_messages ->
        injected =
          Enum.map(pending_messages, fn content ->
            %{role: :user, content: content}
          end)

        {:ok, %{messages: request.messages ++ injected}}
    end
  end
end
