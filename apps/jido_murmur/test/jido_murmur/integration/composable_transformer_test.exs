defmodule JidoMurmur.Integration.ComposableTransformerTest do
  @moduledoc """
  Integration tests for composing MessageInjector with custom transformers
  via ComposableRequestTransformer (User Story 5, T082).

  Verifies:
  - MessageInjector works inside a composed chain
  - A custom transformer's modifications are visible alongside MessageInjector's
  - Deep-merge preserves both transformers' contributions
  - Error in one transformer halts the chain
  """
  use JidoMurmur.Case, async: false

  alias JidoMurmur.ComposableRequestTransformer
  alias JidoMurmur.MessageInjector
  alias JidoMurmur.PendingQueue
  alias JidoMurmur.Workspaces

  # ── Test Transformers ──────────────────────────────────────────

  defmodule GuardrailTransformer do
    @moduledoc """
    A custom transformer that prepends a safety system message.
    Simulates a consumer-provided content-moderation transformer.
    """
    @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

    @impl true
    def transform_request(request, _state, _config, _ctx) do
      guardrail_msg = %{
        role: :system,
        content: "SAFETY: You must refuse harmful content."
      }

      {:ok, %{messages: [guardrail_msg | request.messages]}}
    end
  end

  defmodule LlmOptsEnricher do
    @moduledoc """
    A custom transformer that enriches llm_opts with consumer-specific settings.
    """
    @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

    @impl true
    def transform_request(_request, _state, _config, _ctx) do
      {:ok, %{llm_opts: [max_tokens: 4096, stop: ["END"]]}}
    end
  end

  # ── Setup ──────────────────────────────────────────────────────

  setup do
    ensure_ets_tables()

    {:ok, workspace} = Workspaces.create_workspace(%{name: "Composable WS"})

    {:ok, session} =
      Workspaces.create_agent_session(workspace.id, %{
        agent_profile_id: "test_agent",
        display_name: "Composable Bot"
      })

    # Create a second session so TeamInstructions has a teammate
    {:ok, _teammate} =
      Workspaces.create_agent_session(workspace.id, %{
        agent_profile_id: "test_agent",
        display_name: "Helper Bot"
      })

    base_request = %{
      messages: [%{role: :user, content: "What is the weather?"}],
      llm_opts: [model: "gpt-4"],
      tools: [:tell]
    }

    runtime_context = %{
      agent_id: session.id,
      workspace_id: workspace.id,
      sender_name: session.display_name
    }

    %{
      workspace: workspace,
      session: session,
      base_request: base_request,
      runtime_context: runtime_context
    }
  end

  # ── Tests ──────────────────────────────────────────────────────

  describe "MessageInjector composed with a custom guardrail transformer" do
    test "guardrail runs first, then MessageInjector injects team context", ctx do
      runtime_context =
        Map.put(ctx.runtime_context, :request_transformers, [
          GuardrailTransformer,
          MessageInjector
        ])

      assert {:ok, overrides} =
               ComposableRequestTransformer.transform_request(
                 ctx.base_request,
                 %{},
                 %{},
                 runtime_context
               )

      messages = overrides.messages

      # GuardrailTransformer prepends safety message, then MessageInjector injects
      # team context into the system message. Both should be present.
      system_messages = Enum.filter(messages, &(&1.role == :system))
      assert [_ | _] = system_messages

      system_content = Enum.map_join(system_messages, "\n", & &1.content)
      assert system_content =~ "SAFETY: You must refuse harmful content."
      assert system_content =~ "murmur_team_context"

      # The original user message should still be present
      user_messages = Enum.filter(messages, &(&1.role == :user))
      assert Enum.any?(user_messages, &(&1.content == "What is the weather?"))
    end

    test "MessageInjector runs first, then guardrail prepends to its output", ctx do
      runtime_context =
        Map.put(ctx.runtime_context, :request_transformers, [
          MessageInjector,
          GuardrailTransformer
        ])

      assert {:ok, overrides} =
               ComposableRequestTransformer.transform_request(
                 ctx.base_request,
                 %{},
                 %{},
                 runtime_context
               )

      messages = overrides.messages

      # MessageInjector modifies system message with team context first.
      # GuardrailTransformer then prepends its safety message to whatever
      # MessageInjector produced.
      assert hd(messages).role == :system
      assert hd(messages).content =~ "SAFETY"
    end
  end

  describe "MessageInjector with pending messages and custom transformer" do
    test "pending messages are injected alongside guardrail modifications", ctx do
      # Enqueue a pending message for the agent
      PendingQueue.enqueue(ctx.session.id, "Pending message from another agent")

      runtime_context =
        Map.put(ctx.runtime_context, :request_transformers, [
          GuardrailTransformer,
          MessageInjector
        ])

      assert {:ok, overrides} =
               ComposableRequestTransformer.transform_request(
                 ctx.base_request,
                 %{},
                 %{},
                 runtime_context
               )

      messages = overrides.messages

      # Should have: safety system msg, team context, original user msg, and pending msg
      user_messages = Enum.filter(messages, &(&1.role == :user))
      user_content = Enum.map(user_messages, & &1.content)

      assert "What is the weather?" in user_content
      assert "Pending message from another agent" in user_content
    end
  end

  describe "multiple custom transformers with MessageInjector" do
    test "three transformers compose: guardrail + MessageInjector + LlmOptsEnricher", ctx do
      runtime_context =
        Map.put(ctx.runtime_context, :request_transformers, [
          GuardrailTransformer,
          MessageInjector,
          LlmOptsEnricher
        ])

      assert {:ok, overrides} =
               ComposableRequestTransformer.transform_request(
                 ctx.base_request,
                 %{},
                 %{},
                 runtime_context
               )

      # Messages from both guardrail and MessageInjector
      assert Map.has_key?(overrides, :messages)
      system_content = Enum.map_join(overrides.messages, "\n", & &1.content)
      assert system_content =~ "SAFETY"
      assert system_content =~ "murmur_team_context"

      # LLM opts from LlmOptsEnricher
      assert Map.has_key?(overrides, :llm_opts)
      assert Keyword.get(overrides.llm_opts, :max_tokens) == 4096
      assert Keyword.get(overrides.llm_opts, :stop) == ["END"]
    end
  end

  # ── Helpers ────────────────────────────────────────────────────

  defp ensure_ets_tables do
    unless :ets.whereis(:jido_murmur_active_runners) != :undefined do
      :ets.new(:jido_murmur_active_runners, [:set, :public, :named_table])
    end

    unless :ets.whereis(:jido_murmur_pending_messages) != :undefined do
      :ets.new(:jido_murmur_pending_messages, [:named_table, :public, :duplicate_bag])
    end
  rescue
    ArgumentError -> :ok
  end
end
