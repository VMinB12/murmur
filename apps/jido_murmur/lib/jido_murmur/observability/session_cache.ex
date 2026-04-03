defmodule JidoMurmur.Observability.SessionCache do
  @moduledoc """
  ETS-backed cache mapping agent session IDs to workspace and display name.
  """

  @table :jido_murmur_obs_sessions

  def create_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    else
      @table
    end
  end

  def put(agent_id, workspace_id, display_name) do
    :ets.insert(@table, {agent_id, workspace_id, display_name})
    :ok
  end

  def lookup(agent_id) do
    case :ets.lookup(@table, agent_id) do
      [{^agent_id, workspace_id, display_name}] -> {workspace_id, display_name}
      [] -> nil
    end
  end

  def delete(agent_id) do
    :ets.delete(@table, agent_id)
    :ok
  end
end
