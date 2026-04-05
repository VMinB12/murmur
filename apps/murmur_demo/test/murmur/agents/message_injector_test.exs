defmodule Murmur.Agents.MessageInjectorTest do
  @moduledoc """
  Tests for the MessageInjector request transformer.

  MessageInjector is now responsible only for adding Murmur's dynamic
  team-context system prompt to ReAct requests.
  """
  use Murmur.DataCase, async: false

  alias JidoMurmur.MessageInjector
  alias JidoMurmur.Observability.Store
  alias JidoMurmur.Workspaces

  defmodule FakeState do
    @moduledoc false
    defstruct [:run_id, :request_id, :iteration, :context, :llm_call_id]
  end

  defmodule FakeConfig do
    @moduledoc false
    defstruct [:request_transformer, :model, :tools]
  end

  setup do
    Store.create_tables()

    {:ok, workspace} = Workspaces.create_workspace(%{name: "Injector Test Workspace"})

    {:ok, session} =
      Workspaces.create_agent_session(workspace.id, %{
        agent_profile_id: "general_agent",
        display_name: "Alice"
      })

    {:ok, _teammate} =
      Workspaces.create_agent_session(workspace.id, %{
        agent_profile_id: "general_agent",
        display_name: "Bob"
      })

    %{workspace: workspace, session: session}
  end

  describe "transform_request/4" do
    test "returns unchanged messages when workspace context is missing" do
      messages = [
        %{role: :system, content: "You are helpful."},
        %{role: :user, content: "Hello"}
      ]

      request = %{messages: messages, llm_opts: [], tools: %{}}

      assert {:ok, overrides} =
               MessageInjector.transform_request(request, %FakeState{iteration: 1}, %FakeConfig{}, %{})

      assert overrides == %{}
    end

    test "appends team context to an existing system message", %{workspace: workspace, session: session} do
      request = %{
        messages: [
          %{role: :system, content: "You are helpful."},
          %{role: :user, content: "Hello"}
        ],
        llm_opts: [],
        tools: %{}
      }

      runtime_context = %{workspace_id: workspace.id, sender_name: session.display_name}

      assert {:ok, overrides} =
               MessageInjector.transform_request(
                 request,
                 %FakeState{iteration: 1},
                 %FakeConfig{},
                 runtime_context
               )

      [system | rest] = overrides.messages
      assert system.role == :system
      assert system.content =~ "You are helpful."
      assert system.content =~ "<murmur_team_context>"
      assert system.content =~ "Bob"
      assert rest == [%{role: :user, content: "Hello"}]
    end

    test "prepends a system message when the request has none", %{workspace: workspace, session: session} do
      request = %{messages: [%{role: :user, content: "Hello"}], llm_opts: [], tools: %{}}
      runtime_context = %{workspace_id: workspace.id, sender_name: session.display_name}

      assert {:ok, overrides} =
               MessageInjector.transform_request(
                 request,
                 %FakeState{iteration: 1},
                 %FakeConfig{},
                 runtime_context
               )

      [system, user] = overrides.messages
      assert system.role == :system
      assert system.content =~ "<murmur_team_context>"
      assert system.content =~ "Bob"
      assert user == %{role: :user, content: "Hello"}
    end

    test "does not affect tools or llm_opts", %{workspace: workspace, session: session} do
      request = %{
        messages: [%{role: :user, content: "hi"}],
        llm_opts: [temperature: 0.5],
        tools: %{tell: true}
      }

      runtime_context = %{workspace_id: workspace.id, sender_name: session.display_name}

      assert {:ok, overrides} =
               MessageInjector.transform_request(
                 request,
                 %FakeState{iteration: 1},
                 %FakeConfig{},
                 runtime_context
               )

      assert Map.has_key?(overrides, :messages)
      refute Map.has_key?(overrides, :llm_opts)
      refute Map.has_key?(overrides, :tools)
    end

    test "records prepared messages for the current llm_call_id", %{workspace: workspace, session: session} do
      call_id = "llm-call-#{System.unique_integer([:positive])}"

      request = %{
        messages: [%{role: :user, content: "hi"}],
        llm_opts: [temperature: 0.5],
        tools: %{}
      }

      runtime_context = %{workspace_id: workspace.id, sender_name: session.display_name}

      assert {:ok, overrides} =
               MessageInjector.transform_request(
                 request,
                 %FakeState{iteration: 1, llm_call_id: call_id},
                 %FakeConfig{},
                 runtime_context
               )

      assert [{^call_id, messages}] = :ets.lookup(:jido_murmur_obs_prepared_llm_inputs, call_id)
      assert messages == overrides.messages
      assert hd(messages).content =~ "<murmur_team_context>"
    end
  end
end
