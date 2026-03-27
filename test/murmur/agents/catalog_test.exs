defmodule Murmur.Agents.CatalogTest do
  @moduledoc """
  Tests for the agent catalog.

  Covers:
  - FR-001: System MUST provide a catalog of predefined agent profiles
  """
  use ExUnit.Case, async: true

  alias Murmur.Agents.Catalog
  alias Murmur.Agents.MessageInjector
  alias Murmur.Agents.Profiles.ArxivAgent
  alias Murmur.Agents.Profiles.GeneralAgent
  alias Murmur.Agents.TellAction

  describe "list_profiles/0" do
    test "returns a non-empty list of profiles" do
      profiles = Catalog.list_profiles()
      assert length(profiles) >= 2
    end

    test "each profile has required fields" do
      for profile <- Catalog.list_profiles() do
        assert Map.has_key?(profile, :id)
        assert Map.has_key?(profile, :description)
        assert Map.has_key?(profile, :color)
        assert is_binary(profile.id)
        assert is_binary(profile.description)
      end
    end

    test "includes general_agent profile" do
      profiles = Catalog.list_profiles()
      ids = Enum.map(profiles, & &1.id)
      assert "general_agent" in ids
    end

    test "includes arxiv_agent profile" do
      profiles = Catalog.list_profiles()
      ids = Enum.map(profiles, & &1.id)
      assert "arxiv_agent" in ids
    end
  end

  describe "get_profile!/1" do
    test "returns profile details for a valid id" do
      profile = Catalog.get_profile!("general_agent")
      assert profile.id == "general_agent"
      assert is_atom(profile.agent_module)
      assert is_binary(profile.description)
      assert is_binary(profile.color)
    end

    test "raises for unknown profile id" do
      assert_raise RuntimeError, ~r/Unknown agent profile/, fn ->
        Catalog.get_profile!("nonexistent")
      end
    end
  end

  describe "agent_module/1" do
    test "returns the module for general_agent" do
      assert Catalog.agent_module("general_agent") == GeneralAgent
    end

    test "returns the module for arxiv_agent" do
      assert Catalog.agent_module("arxiv_agent") == ArxivAgent
    end

    test "raises for unknown profile id" do
      assert_raise RuntimeError, ~r/Unknown agent profile/, fn ->
        Catalog.agent_module("nonexistent")
      end
    end
  end

  describe "agent profiles have required capabilities" do
    test "GeneralAgent module is a valid Jido.AI.Agent" do
      Code.ensure_loaded!(GeneralAgent)
      assert function_exported?(GeneralAgent, :ask, 3)
      assert function_exported?(GeneralAgent, :await, 2)
    end

    test "ArxivAgent module is a valid Jido.AI.Agent" do
      Code.ensure_loaded!(ArxivAgent)
      assert function_exported?(ArxivAgent, :ask, 3)
      assert function_exported?(ArxivAgent, :await, 2)
    end

    test "all profile modules export catalog_meta/0 with required fields" do
      for mod <- [GeneralAgent, ArxivAgent] do
        assert function_exported?(mod, :catalog_meta, 0),
               "#{inspect(mod)} must export catalog_meta/0"

        meta = mod.catalog_meta()
        assert is_binary(meta.color), "#{inspect(mod)}.catalog_meta().color must be a string"
      end
    end

    test "MessageInjector exports transform_request/4" do
      Code.ensure_loaded!(MessageInjector)
      assert function_exported?(MessageInjector, :transform_request, 4)
    end

    test "TellAction is a valid Jido.Action" do
      Code.ensure_loaded!(TellAction)
      assert function_exported?(TellAction, :run, 2)
    end
  end
end
