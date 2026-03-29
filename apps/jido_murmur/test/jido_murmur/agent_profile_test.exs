defmodule JidoMurmur.AgentProfileTest do
  use ExUnit.Case, async: true

  alias JidoMurmur.AgentProfile

  describe "behaviour definition" do
    test "exports all callback definitions" do
      callbacks = AgentProfile.behaviour_info(:callbacks)

      assert {:name, 0} in callbacks
      assert {:description, 0} in callbacks
      assert {:plugins, 0} in callbacks
      assert {:actions, 0} in callbacks
      assert {:catalog_meta, 0} in callbacks
    end

    test "module implementing all callbacks compiles without warnings" do
      defmodule TestProfile do
        @behaviour JidoMurmur.AgentProfile

        @impl true
        def name, do: "Test Agent"
        @impl true
        def description, do: "A test agent"
        @impl true
        def plugins, do: []
        @impl true
        def actions, do: []
        @impl true
        def catalog_meta, do: %{color: "green"}
      end

      assert TestProfile.name() == "Test Agent"
      assert TestProfile.plugins() == []
    end
  end
end
