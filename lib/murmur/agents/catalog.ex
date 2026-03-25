defmodule Murmur.Agents.Catalog do
  @moduledoc "Maps agent profile IDs to their module and display metadata."

  @profiles %{
    "general_agent" => {
      Murmur.Agents.Profiles.GeneralAgent,
      %{description: "A helpful general-purpose assistant", color: "blue"}
    },
    "code_agent" => {
      Murmur.Agents.Profiles.CodeAgent,
      %{description: "An expert programmer for code review and debugging", color: "emerald"}
    }
  }

  def list_profiles do
    Enum.map(@profiles, fn {id, {_module, meta}} ->
      Map.put(meta, :id, id)
    end)
  end

  def get_profile!(id) do
    case Map.fetch(@profiles, id) do
      {:ok, {module, meta}} ->
        %{id: id, agent_module: module, description: meta.description, color: meta.color}

      :error ->
        raise "Unknown agent profile: #{id}"
    end
  end

  def agent_module(profile_id) do
    case Map.fetch(@profiles, profile_id) do
      {:ok, {module, _meta}} -> module
      :error -> raise "Unknown agent profile: #{profile_id}"
    end
  end
end
