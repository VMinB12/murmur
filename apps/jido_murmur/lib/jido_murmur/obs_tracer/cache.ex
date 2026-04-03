defmodule JidoMurmur.ObsTracer.Cache do
  @moduledoc false

  alias JidoMurmur.Observability.SessionCache

  def create_table, do: SessionCache.create_table()
  def put(agent_id, workspace_id, display_name), do: SessionCache.put(agent_id, workspace_id, display_name)
  def lookup(agent_id), do: SessionCache.lookup(agent_id)
  def delete(agent_id), do: SessionCache.delete(agent_id)
end
