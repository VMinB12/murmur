defmodule JidoMurmur.RunnerTest do
  use JidoMurmur.Case, async: false

  alias JidoMurmur.Ingress
  alias JidoMurmur.Observability.Store
  alias JidoMurmur.Runner

  setup do
    # Ensure ETS tables exist (TableOwner creates them in prod)
    ensure_ets_tables()

    # Use mock LLM adapter
    Application.put_env(:jido_murmur, :llm_adapter, JidoMurmur.LLM.Mock)
    Application.put_env(:jido_murmur, :skip_hibernate, true)

    on_exit(fn ->
      Application.put_env(:jido_murmur, :llm_adapter, JidoMurmur.LLM.Mock)
      Application.put_env(:jido_murmur, :skip_hibernate, true)
    end)

    :ok
  end

  describe "Ingress.deliver/2" do
    test "returns :agent_not_running when agent is not started" do
      session = build_session()
      assert :agent_not_running = Ingress.deliver(session, "hello")
    end

    test "returns :queued when agent is running" do
      session = insert_session!()
      start_test_agent!(session)

      assert :queued = Ingress.deliver(session, "hello")
    end
  end

  describe "active?/1" do
    test "returns false when no active run task is running" do
      refute Runner.active?("nonexistent-session-id")
    end
  end

  # --- Helpers ---

  defp build_session do
    %JidoMurmur.Workspaces.AgentSession{
      id: Ecto.UUID.generate(),
      workspace_id: Ecto.UUID.generate(),
      agent_profile_id: "test_agent",
      display_name: "Test Agent",
      status: :idle
    }
  end

  defp insert_session! do
    {:ok, workspace} = JidoMurmur.Workspaces.create_workspace(%{name: "Test Workspace"})

    {:ok, session} =
      JidoMurmur.Workspaces.create_agent_session(workspace.id, %{
        agent_profile_id: "test_agent",
        display_name: "Test Agent"
      })

    session
  end

  defp start_test_agent!(session) do
    jido_mod = JidoMurmur.jido_mod()

    # Configure a test profile so Catalog.agent_module works
    profiles = Application.get_env(:jido_murmur, :profiles, [])

    unless Enum.any?(profiles, fn mod -> mod.name() == "test_agent" end) do
      Application.put_env(:jido_murmur, :profiles, [JidoMurmur.TestAgent | profiles])
    end

    jido_mod.start_agent(JidoMurmur.TestAgent, id: session.id)
  end

  defp ensure_ets_tables do
    unless :ets.whereis(:jido_murmur_active_runners) != :undefined do
      :ets.new(:jido_murmur_active_runners, [:set, :public, :named_table])
    end

    Store.create_tables()
  rescue
    ArgumentError -> :ok
  end
end
