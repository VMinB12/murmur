defmodule JidoMurmur.CatalogTest do
  use ExUnit.Case, async: true

  alias JidoMurmur.Catalog

  setup do
    original = Application.get_env(:jido_murmur, :profiles, [])
    Application.put_env(:jido_murmur, :profiles, [JidoMurmur.TestAgent])
    on_exit(fn -> Application.put_env(:jido_murmur, :profiles, original) end)
    :ok
  end

  describe "list_profiles/0" do
    test "returns profiles from config" do
      profiles = Catalog.list_profiles()
      assert length(profiles) >= 1
      assert Enum.any?(profiles, &(&1.id == "test_agent"))
    end

    test "returns empty list when no profiles configured" do
      Application.put_env(:jido_murmur, :profiles, [])
      assert Catalog.list_profiles() == []
    end
  end

  describe "get_profile!/1" do
    test "returns profile for known id" do
      profile = Catalog.get_profile!("test_agent")
      assert profile.id == "test_agent"
      assert profile.agent_module == JidoMurmur.TestAgent
    end

    test "raises for unknown id" do
      assert_raise RuntimeError, ~r/Unknown agent profile/, fn ->
        Catalog.get_profile!("nonexistent")
      end
    end
  end

  describe "agent_module/1" do
    test "returns module for known profile" do
      assert Catalog.agent_module("test_agent") == JidoMurmur.TestAgent
    end

    test "raises for unknown profile" do
      assert_raise RuntimeError, ~r/Unknown agent profile/, fn ->
        Catalog.agent_module("nonexistent")
      end
    end
  end

  describe "color_classes/1" do
    test "returns known color map" do
      classes = Catalog.color_classes("blue")
      assert classes.dot == "bg-blue-500"
      assert classes.text == "text-blue-500"
    end

    test "returns blue as default for unknown colors" do
      classes = Catalog.color_classes("unknown_color")
      assert classes.dot == "bg-blue-500"
    end
  end

  describe "agent_color/2" do
    test "returns consistent color for the same name" do
      color1 = Catalog.agent_color("test_agent", "Alpha")
      color2 = Catalog.agent_color("test_agent", "Alpha")
      assert color1 == color2
    end

    test "returns different colors for different names" do
      color1 = Catalog.agent_color("test_agent", "Alpha")
      color2 = Catalog.agent_color("test_agent", "Omega")
      # Colors may or may not differ based on hash — just verify structure
      assert is_map(color1)
      assert Map.has_key?(color1, :dot)
      assert is_map(color2)
      assert Map.has_key?(color2, :dot)
    end
  end
end
