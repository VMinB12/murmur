defmodule Murmur.Agents.Runner do
  @moduledoc """
  Manages the ask/await lifecycle for an agent session.

  Two paths exist for message delivery:

  1. **Idle agent** — `ask()` succeeds, starts an await loop. After the
     loop completes, any messages that arrived mid-turn (drained by
     `MessageInjector` already) or accumulated post-completion are
     drained and fed into a new loop.

  2. **Busy agent** — `ask()` is rejected. The message is enqueued in
     `PendingQueue`. The `MessageInjector` (a ReAct request_transformer
     configured on every agent profile) drains the queue before the
     next LLM call, injecting the message into the conversation
     mid-turn. No error is surfaced.
  """

  alias Murmur.Agents.{Catalog, PendingQueue}

  require Logger

  @doc """
  Send a message to an agent session.

  Returns `:started` if a new loop was kicked off, `:queued` if the
  message was added to the pending queue for mid-turn injection,
  or `:agent_not_running`.
  """
  def send_message(session, content) do
    pid = Murmur.Jido.whereis(session.id)

    if pid do
      agent_module = Catalog.agent_module(session.agent_profile_id)
      topic = agent_topic(session)

      tool_ctx = %{
        workspace_id: session.workspace_id,
        sender_name: session.display_name
      }

      case do_ask(agent_module, pid, content, tool_ctx) do
        {:ok, req} ->
          start_await_loop(agent_module, pid, req, tool_ctx, session, topic, content)
          :started

        {:error, reason} ->
          broadcast(topic, {:request_failed, session.id, reason})
          :started
      end
    else
      :agent_not_running
    end
  end

  # --- Private ---

  defp start_await_loop(agent_module, pid, req, tool_ctx, session, topic, content) do
    Task.Supervisor.start_child(Murmur.Jido.task_supervisor_name(), fn ->
      result = await_result(agent_module, req)
      handle_result(result, agent_module, pid, tool_ctx, session, topic, content)
    end)
  end

  defp handle_result({:ok, response}, agent_module, pid, tool_ctx, session, topic, _content) do
    hibernate_agent(session.id)
    broadcast(topic, {:message_completed, session.id, response})
    drain_and_continue(agent_module, pid, tool_ctx, session, topic)
  end

  # Busy rejection from ReAct strategy — re-enqueue for mid-turn injection.
  # The MessageInjector will pick it up on the next LLM call.
  defp handle_result(
         {:error, {:rejected, :busy, _}},
         _agent_module,
         _pid,
         _tool_ctx,
         session,
         _topic,
         content
       ) do
    PendingQueue.enqueue(session.id, content)
  end

  defp handle_result({:error, reason}, agent_module, pid, tool_ctx, session, topic, _content) do
    broadcast(topic, {:request_failed, session.id, reason})
    drain_and_continue(agent_module, pid, tool_ctx, session, topic)
  end

  defp drain_and_continue(agent_module, pid, tool_ctx, session, topic) do
    case PendingQueue.drain(session.id) do
      [] ->
        :ok

      pending ->
        combined = Enum.join(pending, "\n\n")
        broadcast(topic, {:status_change, session.id, :busy})

        case do_ask(agent_module, pid, combined, tool_ctx) do
          {:ok, req} ->
            result = await_result(agent_module, req)
            handle_result(result, agent_module, pid, tool_ctx, session, topic, combined)

          {:error, {:rejected, :busy, _}} ->
            PendingQueue.enqueue(session.id, combined)

          {:error, reason} ->
            broadcast(topic, {:request_failed, session.id, reason})
        end
    end
  end

  defp do_ask(agent_module, pid, content, tool_ctx) do
    agent_module.ask(pid, content, tool_context: tool_ctx)
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp await_result(agent_module, req) do
    agent_module.await(req, timeout: 120_000)
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp hibernate_agent(session_id) do
    pid = Murmur.Jido.whereis(session_id)

    if pid do
      case Jido.AgentServer.state(pid) do
        {:ok, %{agent: agent}} -> Murmur.Jido.hibernate(agent)
        _ -> :ok
      end
    end
  rescue
    _ -> :ok
  end

  defp agent_topic(session) do
    "workspace:#{session.workspace_id}:agent:#{session.id}"
  end

  defp broadcast(topic, message) do
    Phoenix.PubSub.broadcast(Murmur.PubSub, topic, message)
  end
end
