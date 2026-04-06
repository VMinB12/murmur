defmodule JidoMurmur.Topics do
  @moduledoc """
  Centralized PubSub topic construction for the Murmur platform.

  All PubSub topics follow the `workspace:{wid}:...` hierarchy.
  No inline topic strings should exist outside this module.
  """

  @spec agent_artifacts(String.t(), String.t()) :: String.t()
  def agent_artifacts(workspace_id, session_id),
    do: "workspace:#{workspace_id}:agent:#{session_id}:artifacts"

  @spec agent_stream(String.t(), String.t()) :: String.t()
  def agent_stream(workspace_id, session_id),
    do: "workspace:#{workspace_id}:agent:#{session_id}:stream"

  @spec agent_messages(String.t(), String.t()) :: String.t()
  def agent_messages(workspace_id, session_id),
    do: "workspace:#{workspace_id}:agent:#{session_id}:messages"

  @spec agent_conversation(String.t(), String.t()) :: String.t()
  def agent_conversation(workspace_id, session_id),
    do: "workspace:#{workspace_id}:agent:#{session_id}:conversation"

  @spec workspace_tasks(String.t()) :: String.t()
  def workspace_tasks(workspace_id),
    do: "workspace:#{workspace_id}:tasks"

  @spec workspace(String.t()) :: String.t()
  def workspace(workspace_id),
    do: "workspace:#{workspace_id}"
end
