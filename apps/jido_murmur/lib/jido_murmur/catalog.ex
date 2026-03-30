defmodule JidoMurmur.Catalog do
  @moduledoc """
  Config-driven agent profile registry.

  Profiles are registered via application config:

      config :jido_murmur, profiles: [MyApp.Agents.GeneralAgent, MyApp.Agents.ArxivAgent]

  Each profile module must implement `name/0` and `description/0`.
  """

  @color_palette ~w(blue emerald violet amber rose cyan fuchsia lime)

  @color_map %{
    "blue" => %{
      dot: "bg-blue-500",
      text: "text-blue-500",
      bg: "bg-blue-500/10",
      header: "border-blue-500/20 bg-blue-500/5"
    },
    "emerald" => %{
      dot: "bg-emerald-500",
      text: "text-emerald-500",
      bg: "bg-emerald-500/10",
      header: "border-emerald-500/20 bg-emerald-500/5"
    },
    "violet" => %{
      dot: "bg-violet-500",
      text: "text-violet-500",
      bg: "bg-violet-500/10",
      header: "border-violet-500/20 bg-violet-500/5"
    },
    "amber" => %{
      dot: "bg-amber-500",
      text: "text-amber-500",
      bg: "bg-amber-500/10",
      header: "border-amber-500/20 bg-amber-500/5"
    },
    "rose" => %{
      dot: "bg-rose-500",
      text: "text-rose-500",
      bg: "bg-rose-500/10",
      header: "border-rose-500/20 bg-rose-500/5"
    },
    "cyan" => %{
      dot: "bg-cyan-500",
      text: "text-cyan-500",
      bg: "bg-cyan-500/10",
      header: "border-cyan-500/20 bg-cyan-500/5"
    },
    "fuchsia" => %{
      dot: "bg-fuchsia-500",
      text: "text-fuchsia-500",
      bg: "bg-fuchsia-500/10",
      header: "border-fuchsia-500/20 bg-fuchsia-500/5"
    },
    "lime" => %{
      dot: "bg-lime-500",
      text: "text-lime-500",
      bg: "bg-lime-500/10",
      header: "border-lime-500/20 bg-lime-500/5"
    }
  }

  @doc "List all registered agent profiles from config."
  def list_profiles do
    profile_modules()
    |> Enum.map(fn mod ->
      %{id: mod.name(), description: mod.description()}
    end)
  end

  @doc "Get a specific profile by ID."
  def get_profile!(id) do
    case find_module(id) do
      nil ->
        raise "Unknown agent profile: #{id}"

      mod ->
        %{id: id, agent_module: mod, description: mod.description()}
    end
  end

  @doc "Get the agent module for a profile."
  def agent_module(profile_id) do
    case find_module(profile_id) do
      nil -> raise "Unknown agent profile: #{profile_id}"
      mod -> mod
    end
  end

  defp find_module(profile_id) do
    Enum.find(profile_modules(), fn mod -> mod.name() == profile_id end)
  end

  defp profile_modules do
    Application.get_env(:jido_murmur, :profiles, [])
  end

  @doc "Returns Tailwind CSS classes for a given color name."
  def color_classes(color) do
    Map.get(@color_map, color, @color_map["blue"])
  end

  @doc "Returns color classes for the given agent, using name-based hashing for unique colors."
  def agent_color(_profile_id, agent_name) do
    idx = :erlang.phash2({:agent_color, agent_name}, length(@color_palette))
    color = Enum.at(@color_palette, idx)
    color_classes(color)
  end
end
