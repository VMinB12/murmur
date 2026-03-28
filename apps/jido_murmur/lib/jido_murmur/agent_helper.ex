defmodule JidoMurmur.AgentHelper do
  @moduledoc """
  Convenience functions for common agent lifecycle operations.

  These return Jido-native types (pids, Signal structs, Thread entries).
  Consumers can always bypass these helpers and call Jido APIs directly.
  """

  alias JidoMurmur.Catalog
  alias JidoMurmur.StreamingPlugin
  alias JidoMurmur.Artifact
  alias JidoMurmur.UITurn

  require Logger

  @doc """
  Start an agent process for a session.

  Tries to restore the agent from storage (checkpoint) first so it retains
  conversation history. Falls back to a fresh agent if no checkpoint exists.

  Returns `{:ok, pid}` or `{:error, reason}`.
  """
  def start_agent(session) do
    jido_mod = JidoMurmur.jido_mod()
    agent_module = Catalog.agent_module(session.agent_profile_id)

    case jido_mod.whereis(session.id) do
      nil ->
        {agent, extra_opts} =
          case jido_mod.thaw(agent_module, session.id) do
            {:ok, thawed_agent} -> {thawed_agent, [agent_module: agent_module]}
            {:error, :not_found} -> {agent_module, []}
          end

        :telemetry.execute(
          [:jido_murmur, :agent, :start],
          %{system_time: System.system_time()},
          %{session_id: session.id, agent_module: agent_module}
        )

        jido_mod.start_agent(agent, [id: session.id] ++ extra_opts)

      pid ->
        {:ok, pid}
    end
  end

  @doc """
  Load messages from an agent's thread, projected into UI-ready format.

  Tries the live agent process first, then falls back to persisted storage.
  """
  def load_messages(session) do
    jido_mod = JidoMurmur.jido_mod()
    pid = jido_mod.whereis(session.id)

    if pid do
      case Jido.AgentServer.state(pid) do
        {:ok, %{agent: agent}} -> project_thread(agent)
        _ -> load_messages_from_storage(session)
      end
    else
      load_messages_from_storage(session)
    end
  end

  @doc """
  Load artifacts from an agent's state.

  Tries the live agent process first, then falls back to persisted storage.
  """
  def load_artifacts(session) do
    jido_mod = JidoMurmur.jido_mod()
    pid = jido_mod.whereis(session.id)

    if pid do
      case Jido.AgentServer.state(pid) do
        {:ok, %{agent: agent}} -> extract_artifacts(agent)
        _ -> load_artifacts_from_storage(session)
      end
    else
      load_artifacts_from_storage(session)
    end
  end

  @doc "Subscribe to all PubSub topics for a session (workspace agent, streaming, artifacts)."
  def subscribe(session) do
    pubsub = JidoMurmur.pubsub()
    topic = "workspace:#{session.workspace_id}:agent:#{session.id}"
    Phoenix.PubSub.subscribe(pubsub, topic)
    Phoenix.PubSub.subscribe(pubsub, StreamingPlugin.stream_topic(session.id))
    Phoenix.PubSub.subscribe(pubsub, Artifact.artifact_topic(session.id))
    :ok
  end

  @doc "Subscribe to workspace-level PubSub topics."
  def subscribe_workspace(workspace_id) do
    pubsub = JidoMurmur.pubsub()
    Phoenix.PubSub.subscribe(pubsub, "workspace:#{workspace_id}")
    :ok
  end

  @doc "Clean up storage for a workspace (delete threads, checkpoints for all sessions)."
  def cleanup_workspace_storage(workspace_id) do
    sessions = JidoMurmur.Workspaces.list_agent_sessions(workspace_id)
    {adapter, opts} = JidoMurmur.jido_mod().__jido_storage__()

    Enum.each(sessions, fn session ->
      agent_module = Catalog.agent_module(session.agent_profile_id)
      checkpoint_key = {agent_module, session.id}

      adapter.delete_checkpoint(checkpoint_key, opts)
      adapter.delete_thread(session.id, opts)
    end)

    :ok
  rescue
    e ->
      Logger.warning("Failed to cleanup workspace storage: #{Exception.message(e)}")
      :ok
  end

  # --- Private Helpers ---

  defp load_messages_from_storage(session) do
    jido_mod = JidoMurmur.jido_mod()
    agent_module = Catalog.agent_module(session.agent_profile_id)

    case jido_mod.thaw(agent_module, session.id) do
      {:ok, agent} -> project_thread(agent)
      {:error, :not_found} -> []
    end
  end

  defp project_thread(agent) do
    thread = get_in_thread(agent)

    if thread do
      UITurn.project_entries(thread.entries)
    else
      []
    end
  end

  defp get_in_thread(%{state: %{__thread__: thread}}) when not is_nil(thread), do: thread
  defp get_in_thread(_), do: nil

  defp load_artifacts_from_storage(session) do
    jido_mod = JidoMurmur.jido_mod()
    agent_module = Catalog.agent_module(session.agent_profile_id)

    case jido_mod.thaw(agent_module, session.id) do
      {:ok, agent} -> extract_artifacts(agent)
      {:error, :not_found} -> %{}
    end
  end

  defp extract_artifacts(%{state: %{artifacts: artifacts}}) when is_map(artifacts), do: artifacts
  defp extract_artifacts(_), do: %{}
end
