defmodule Murmur.Agents.PubSubBridge do
  @moduledoc """
  Bridges Jido AgentServer signals to Phoenix PubSub.

  Subscribes the calling process to the agent's internal signal bus and
  forwards relevant ReAct events to the workspace-scoped PubSub topic.
  """

  alias Murmur.Agents.Catalog

  def topic(workspace_id, agent_session_id) do
    "workspace:#{workspace_id}:agent:#{agent_session_id}"
  end

  @doc """
  Starts an agent for the given session and wires up PubSub broadcasting.
  Returns `{:ok, pid}` or `{:error, reason}`.
  """
  def start_agent(agent_session) do
    agent_module = Catalog.agent_module(agent_session.agent_profile_id)

    case Murmur.Jido.start_agent(agent_module, id: agent_session.id) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, {:already_registered, pid}} -> {:ok, pid}
      error -> error
    end
  end

  @doc """
  Sends a user message to the agent via ask/await pattern.
  Spawns a task to handle the async response and broadcast results.
  """
  def send_message(agent_session, user_message) do
    agent_module = Catalog.agent_module(agent_session.agent_profile_id)
    pid = Murmur.Jido.whereis(agent_session.id)

    if pid do
      topic = topic(agent_session.workspace_id, agent_session.id)
      broadcast(topic, {:status_change, agent_session.id, :busy})

      Task.Supervisor.start_child(Murmur.TaskSupervisor, fn ->
        try do
          {:ok, req} = agent_module.ask(pid, user_message)
          result = agent_module.await(req, timeout: 120_000)

          case result do
            {:ok, response} ->
              broadcast(topic, {:message_completed, agent_session.id, response})

            {:error, reason} ->
              broadcast(topic, {:request_failed, agent_session.id, reason})
          end
        rescue
          e ->
            broadcast(topic, {:request_failed, agent_session.id, Exception.message(e)})
        after
          broadcast(topic, {:status_change, agent_session.id, :idle})
        end
      end)

      :ok
    else
      {:error, :agent_not_running}
    end
  end

  def stop_agent(agent_session_id) do
    case Murmur.Jido.whereis(agent_session_id) do
      nil -> :ok
      _pid -> Murmur.Jido.stop_agent(agent_session_id)
    end
  end

  defp broadcast(topic, message) do
    Phoenix.PubSub.broadcast(Murmur.PubSub, topic, message)
  end
end
