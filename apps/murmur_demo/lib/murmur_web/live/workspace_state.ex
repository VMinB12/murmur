defmodule MurmurWeb.Live.WorkspaceState do
  @moduledoc """
  Shared state projection and persistence helpers for the workspace UI.
  """

  alias JidoArtifacts.Envelope
  alias JidoMurmur.AgentHelper
  alias JidoMurmur.Catalog
  alias JidoMurmur.DisplayMessage

  @spec load_messages_for_session(map()) :: list()
  def load_messages_for_session(session) do
    AgentHelper.load_messages(session)
  end

  @spec load_artifacts_for_session(map()) :: map()
  def load_artifacts_for_session(session) do
    AgentHelper.load_artifacts(session)
  end

  @spec extract_artifacts(map()) :: map()
  def extract_artifacts(%{state: %{artifacts: artifacts}}) when is_map(artifacts), do: artifacts
  def extract_artifacts(_agent), do: %{}

  @spec artifact_present?(term()) :: boolean()
  def artifact_present?(%Envelope{data: data}), do: data not in [nil, [], %{}]
  def artifact_present?(_artifact), do: false

  @spec unified_timeline(map(), list()) :: list()
  def unified_timeline(messages_map, agent_sessions) do
    session_index = Map.new(agent_sessions, &{&1.id, &1})

    messages_map
    |> Enum.flat_map(fn {session_id, messages} ->
      session = Map.get(session_index, session_id)
      agent_name = if session, do: session.display_name, else: "unknown"
      profile_id = if session, do: session.agent_profile_id
      agent_color = Catalog.agent_color(profile_id, agent_name)

      Enum.map(messages, fn message ->
        enriched = maybe_attach_assistant_actor(message, agent_name, session_id)

        Map.merge(enriched, %{
          session_id: session_id,
          agent_name: agent_name,
          agent_color: agent_color
        })
      end)
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp maybe_attach_assistant_actor(message, agent_name, session_id) do
    if DisplayMessage.assistant_message?(message) do
      DisplayMessage.with_actor(message, JidoMurmur.ActorIdentity.agent(agent_name, id: session_id), sender_name: agent_name)
    else
      message
    end
  end

  @spec hibernate_agent(String.t()) :: :ok
  def hibernate_agent(session_id) when is_binary(session_id) do
    case Murmur.Jido.whereis(session_id) do
      nil ->
        :ok

      _pid ->
        case Jido.AgentServer.state(Murmur.Jido.whereis(session_id)) do
          {:ok, %{agent: agent}} -> Murmur.Jido.hibernate(agent)
          _ -> :ok
        end
    end
  end

end
