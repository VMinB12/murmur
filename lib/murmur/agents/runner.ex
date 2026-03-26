defmodule Murmur.Agents.Runner do
  @moduledoc """
  Manages the ask/await lifecycle for an agent session.

  All incoming messages are enqueued in `PendingQueue` first. A single
  drain-loop Task per session pulls messages off the queue, combines
  them, and sends exactly ONE `ask()` at a time. This avoids concurrent
  asks which corrupt the agent's `last_request_id` tracking.

  Messages arriving while the LLM is processing are either:
  - Injected mid-turn by `MessageInjector` (before the next LLM call)
  - Picked up by the drain loop after the current request completes
  """

  alias Murmur.Agents.{Catalog, PendingQueue}

  require Logger

  @active_table :murmur_active_runners

  @doc "Initialize the active-runner tracker. Call once at app start."
  def init do
    :ets.new(@active_table, [:set, :public, :named_table])
    :ok
  end

  @doc """
  Send a message to an agent session.

  The message is enqueued and a drain loop is started if one isn't
  already running for this session.

  Returns `:queued` or `:agent_not_running`.
  """
  def send_message(session, content) do
    pid = Murmur.Jido.whereis(session.id)

    if pid do
      PendingQueue.enqueue(session.id, content)
      maybe_start_loop(session)
      :queued
    else
      :agent_not_running
    end
  end

  # --- Private ---

  defp maybe_start_loop(session) do
    if :ets.insert_new(@active_table, {session.id, true}) do
      Task.Supervisor.start_child(Murmur.Jido.task_supervisor_name(), fn ->
        try do
          run_loop(session)
        after
          :ets.delete(@active_table, session.id)
        end
      end)
    end

    :ok
  end

  defp run_loop(session) do
    case PendingQueue.drain(session.id) do
      [] ->
        :done

      messages ->
        process_batch(session, Enum.join(messages, "\n\n"))
        run_loop(session)
    end
  end

  defp process_batch(session, combined) do
    pid = Murmur.Jido.whereis(session.id)
    if is_nil(pid), do: throw(:agent_gone)

    agent_module = Catalog.agent_module(session.agent_profile_id)
    topic = agent_topic(session)

    tool_ctx = %{
      workspace_id: session.workspace_id,
      sender_name: session.display_name
    }

    case do_ask(agent_module, pid, combined, tool_ctx) do
      {:ok, req} ->
        handle_await(agent_module, req, session, topic)

      {:error, reason} ->
        broadcast(topic, {:request_failed, session.id, reason})
    end
  catch
    :agent_gone -> :ok
  end

  defp handle_await(agent_module, req, session, topic) do
    case await_result(agent_module, req) do
      {:ok, response} ->
        hibernate_agent(session.id)
        broadcast(topic, {:message_completed, session.id, response})

      {:error, reason} ->
        broadcast(topic, {:request_failed, session.id, reason})
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
