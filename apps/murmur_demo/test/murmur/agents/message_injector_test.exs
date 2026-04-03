defmodule Murmur.Agents.MessageInjectorTest do
  @moduledoc """
  Tests for the MessageInjector request transformer.

  The MessageInjector is the core mechanism that enables mid-turn message
  injection into a busy agent's conversation. It implements the
  Jido.AI.Reasoning.ReAct.RequestTransformer behaviour and is called
  before every LLM API call within an agent loop.

  The principle: when a message arrives for a busy agent (from a user or
  via the tell tool), it is enqueued in the PendingQueue. The
  MessageInjector drains the queue before each LLM call and appends
  those messages to the conversation history, so the LLM sees them
  on its very next iteration — without waiting for the full agent
  loop to complete.
  """
  use ExUnit.Case, async: true

  alias JidoMurmur.MessageInjector
  alias JidoMurmur.Observability.Store
  alias JidoMurmur.PendingQueue

  # Minimal stubs for the ReAct runner types.
  # The transformer receives these as arguments.
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
    session_id = Ecto.UUID.generate()
    {:ok, session_id: session_id}
  end

  describe "transform_request/4 — core injection" do
    test "returns {:ok, overrides} with unchanged messages when queue is empty", ctx do
      messages = [
        %{role: :system, content: "You are helpful."},
        %{role: :user, content: "Hello"}
      ]

      request = %{messages: messages, llm_opts: [], tools: %{}}
      runtime_context = %{agent_id: ctx.session_id}

      assert {:ok, overrides} =
               MessageInjector.transform_request(
                 request,
                 %FakeState{iteration: 1},
                 %FakeConfig{},
                 runtime_context
               )

      # No overrides needed — messages unchanged
      assert overrides == %{}
    end

    test "drains pending messages and appends them to conversation", ctx do
      PendingQueue.enqueue(ctx.session_id, "urgent update from alice")

      messages = [
        %{role: :system, content: "You are helpful."},
        %{role: :user, content: "Original question"},
        %{role: :assistant, content: "Let me think..."}
      ]

      request = %{messages: messages, llm_opts: [], tools: %{}}
      runtime_context = %{agent_id: ctx.session_id}

      assert {:ok, overrides} =
               MessageInjector.transform_request(
                 request,
                 %FakeState{iteration: 2},
                 %FakeConfig{},
                 runtime_context
               )

      injected_messages = overrides.messages

      # Original messages preserved
      assert Enum.take(injected_messages, 3) == messages

      # Injected message appended at the end
      [injected] = Enum.drop(injected_messages, 3)
      assert injected.role == :user
      assert injected.content =~ "urgent update from alice"
    end

    test "injects multiple pending messages in order", ctx do
      PendingQueue.enqueue(ctx.session_id, "first message")
      PendingQueue.enqueue(ctx.session_id, "second message")

      messages = [%{role: :user, content: "hi"}]
      request = %{messages: messages, llm_opts: [], tools: %{}}
      runtime_context = %{agent_id: ctx.session_id}

      assert {:ok, overrides} =
               MessageInjector.transform_request(
                 request,
                 %FakeState{iteration: 1},
                 %FakeConfig{},
                 runtime_context
               )

      injected = Enum.drop(overrides.messages, 1)
      assert length(injected) == 2
      assert Enum.at(injected, 0).content =~ "first message"
      assert Enum.at(injected, 1).content =~ "second message"
    end

    test "queue is empty after injection (drained atomically)", ctx do
      PendingQueue.enqueue(ctx.session_id, "will be drained")

      request = %{messages: [%{role: :user, content: "hi"}], llm_opts: [], tools: %{}}
      runtime_context = %{agent_id: ctx.session_id}

      {:ok, _} =
        MessageInjector.transform_request(
          request,
          %FakeState{iteration: 1},
          %FakeConfig{},
          runtime_context
        )

      refute PendingQueue.pending?(ctx.session_id)
    end

    test "does not affect tools or llm_opts", ctx do
      PendingQueue.enqueue(ctx.session_id, "injected")

      request = %{
        messages: [%{role: :user, content: "hi"}],
        llm_opts: [temperature: 0.5],
        tools: %{}
      }

      runtime_context = %{agent_id: ctx.session_id}

      assert {:ok, overrides} =
               MessageInjector.transform_request(
                 request,
                 %FakeState{iteration: 1},
                 %FakeConfig{},
                 runtime_context
               )

      # Only :messages is overridden
      refute Map.has_key?(overrides, :llm_opts)
      refute Map.has_key?(overrides, :tools)
    end

    test "records prepared messages for the current llm_call_id", ctx do
      call_id = "llm-call-#{System.unique_integer([:positive])}"

      request = %{
        messages: [%{role: :user, content: "hi"}],
        llm_opts: [temperature: 0.5],
        tools: %{}
      }

      runtime_context = %{agent_id: ctx.session_id}

      assert {:ok, _overrides} =
               MessageInjector.transform_request(
                 request,
                 %FakeState{iteration: 1, llm_call_id: call_id},
                 %FakeConfig{},
                 runtime_context
               )

      assert [{^call_id, messages}] = :ets.lookup(:jido_murmur_obs_prepared_llm_inputs, call_id)
      assert messages == request.messages
    end
  end

  describe "transform_request/4 — agent_id resolution" do
    test "uses agent_id from runtime_context to identify session queue", ctx do
      PendingQueue.enqueue(ctx.session_id, "for this agent")

      other_session = Ecto.UUID.generate()
      PendingQueue.enqueue(other_session, "for other agent")

      request = %{messages: [], llm_opts: [], tools: %{}}
      runtime_context = %{agent_id: ctx.session_id}

      {:ok, overrides} =
        MessageInjector.transform_request(
          request,
          %FakeState{iteration: 1},
          %FakeConfig{},
          runtime_context
        )

      contents = Enum.map(overrides.messages, & &1.content)
      assert Enum.any?(contents, &(&1 =~ "for this agent"))
      refute Enum.any?(contents, &(&1 =~ "for other agent"))

      # Other session's queue untouched
      assert PendingQueue.pending?(other_session)
    end
  end
end
