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

  alias Murmur.Agents.Catalog
  alias Murmur.Agents.PendingQueue

  require Logger

  @active_table :murmur_active_runners

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

    case llm_adapter().ask(agent_module, pid, combined, tool_ctx) do
      {:ok, req} ->
        handle_await(agent_module, req, session, topic)

      {:error, reason} ->
        broadcast(topic, {:request_failed, session.id, reason})
    end
  catch
    :agent_gone -> :ok
  end

  defp handle_await(agent_module, req, session, topic) do
    case llm_adapter().await(agent_module, req, timeout: 120_000) do
      {:ok, response} ->
        hibernate_agent(session.id)
        broadcast(topic, {:message_completed, session.id, response})

      {:error, reason} ->
        broadcast(topic, {:request_failed, session.id, reason})
    end
  end

  defp llm_adapter do
    Application.get_env(:murmur, :llm_adapter, Murmur.Agents.LLM.Real)
  end

  defp hibernate_agent(session_id) do
    if Application.get_env(:murmur, :skip_hibernate, false) do
      :ok
    else
      do_hibernate(session_id)
    end
  end

  defp do_hibernate(session_id) do
    with pid when is_pid(pid) <- Murmur.Jido.whereis(session_id),
         {:ok, %{agent: agent}} <- Jido.AgentServer.state(pid),
         :ok <- Murmur.Jido.hibernate(agent) do
      :ok
    else
      nil -> :ok
      {:error, reason} -> log_hibernate_error(session_id, reason)
    end
  rescue
    e ->
      Logger.error("Exception during hibernate for agent #{session_id}: #{Exception.message(e)}")
      :ok
  catch
    :exit, reason ->
      Logger.error("Exit during hibernate for agent #{session_id}: #{inspect(reason)}")
      :ok
  end

  defp log_hibernate_error(session_id, reason) do
    Logger.error("Failed to hibernate agent #{session_id}: #{inspect(reason)}")
    {:error, reason}
  end

  defp agent_topic(session) do
    "workspace:#{session.workspace_id}:agent:#{session.id}"
  end

  defp broadcast(topic, message) do
    Phoenix.PubSub.broadcast(Murmur.PubSub, topic, message)
  end
end
