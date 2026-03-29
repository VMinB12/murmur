defmodule JidoMurmur.ObsTracer.Cache do
  @moduledoc """
  ETS-backed cache mapping agent session IDs to workspace + display name.

  Populated in `AgentHelper.start_agent/1` when an agent process boots,
  cleaned up on agent termination. Lookups are O(1) with no DB hit.
  """

  @table :jido_murmur_obs_sessions

  @doc "Create the ETS table. Called from `JidoMurmur.TableOwner`."
  def create_table do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
  end

  @doc "Cache an agent session's workspace ID and display name."
  def put(agent_id, workspace_id, display_name) do
    :ets.insert(@table, {agent_id, workspace_id, display_name})
    :ok
  end

  @doc "Look up cached workspace ID and display name for an agent session."
  def lookup(agent_id) do
    case :ets.lookup(@table, agent_id) do
      [{^agent_id, workspace_id, display_name}] -> {workspace_id, display_name}
      [] -> nil
    end
  end

  @doc "Remove a cached agent session entry."
  def delete(agent_id) do
    :ets.delete(@table, agent_id)
    :ok
  end
end
