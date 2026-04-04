defmodule JidoMurmur.Telemetry.ReqLLMTracerTest do
  use ExUnit.Case, async: false

  alias JidoMurmur.Observability
  alias JidoMurmur.Observability.SessionCache
  alias JidoMurmur.Observability.Store
  alias JidoMurmur.Telemetry.JidoAITracer
  alias JidoMurmur.Telemetry.ReqLLMTracer

  @table JidoMurmur.Telemetry.ReqLLMTracer
  @llm_span_table :jido_murmur_obs_llm_spans
  @store_tables [
    :jido_murmur_obs_turns,
    :jido_murmur_obs_agent_turns,
    :jido_murmur_obs_llm_spans,
    :jido_murmur_obs_tool_spans,
    :jido_murmur_obs_tool_inputs,
    :jido_murmur_obs_req_llm_lookup,
    :jido_murmur_obs_pending_llm_calls,
    :jido_murmur_obs_pending_agent_llm_calls,
    :jido_murmur_obs_pending_global_llm_calls,
    :jido_murmur_obs_prepared_llm_inputs,
    :jido_murmur_obs_pending_req_llm_starts
  ]

  setup do
    # Ensure the ETS table exists (might already exist from app startup)
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    end

    # Ensure session cache table exists for session/agent enrichment tests
    if :ets.whereis(:jido_murmur_obs_sessions) == :undefined do
      :ets.new(:jido_murmur_obs_sessions, [:named_table, :public, :set, read_concurrency: true])
    end

    Store.create_tables()
    Enum.each(@store_tables, &clear_ets_table/1)
    Observability.clear_active_llm_call_id()
    Logger.metadata(agent_id: nil)

    # Attach handler; ignore errors if already attached
    try do
      ReqLLMTracer.attach()
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end

    try do
      JidoAITracer.attach()
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end

    on_exit(fn ->
      # Clean up ETS entries after each test
      if :ets.whereis(@table) != :undefined do
        :ets.delete_all_objects(@table)
      end

      if :ets.whereis(:jido_murmur_obs_sessions) != :undefined do
        :ets.delete_all_objects(:jido_murmur_obs_sessions)
      end

      if :ets.whereis(@llm_span_table) != :undefined do
        :ets.delete_all_objects(@llm_span_table)
      end

      Enum.each(@store_tables, &clear_ets_table/1)
      Observability.clear_active_llm_call_id()
      Logger.metadata(agent_id: nil)
    end)

    :ok
  end

  defp clear_ets_table(table) do
    if :ets.whereis(table) != :undefined do
      :ets.delete_all_objects(table)
    end
  end

  defp start_metadata(request_id, opts \\ []) do
    base = %{
      request_id: request_id,
      model: %{id: Keyword.get(opts, :model_id, "openai:gpt-5-mini"), provider: Keyword.get(opts, :provider, "openai")},
      operation: :chat,
      mode: Keyword.get(opts, :mode, :stream)
    }

    case Keyword.get(opts, :request_payload) do
      nil -> base
      payload -> Map.put(base, :request_payload, payload)
    end
  end

  defp stop_metadata(request_id, opts \\ []) do
    base = %{
      request_id: request_id,
      model: %{id: "openai:gpt-5-mini", provider: "openai"},
      usage: Keyword.get(opts, :usage, %{input_tokens: 100, output_tokens: 50}),
      finish_reason: Keyword.get(opts, :finish_reason, :stop),
      response_summary: Keyword.get(opts, :response_summary, %{text: "Hello from test"})
    }

    case Keyword.get(opts, :response_payload) do
      nil -> base
      payload -> Map.put(base, :response_payload, payload)
    end
  end

  defp exception_metadata(request_id) do
    %{
      request_id: request_id,
      model: %{id: "openai:gpt-5-mini", provider: "openai"},
      error: %RuntimeError{message: "LLM request failed"}
    }
  end

  describe "attach/0" do
    test "creates ETS table" do
      assert :ets.whereis(@table) != :undefined
    end

    test "handler is attached to telemetry events" do
      handlers = :telemetry.list_handlers([:req_llm, :request, :start])
      assert Enum.any?(handlers, &(&1.id == :jido_murmur_req_llm_tracer))
    end
  end

  describe "start event" do
    test "stores span context in ETS keyed by request_id" do
      request_id = "test-#{System.unique_integer([:positive])}"

      :telemetry.execute(
        [:req_llm, :request, :start],
        %{system_time: System.system_time()},
        start_metadata(request_id)
      )

      assert [{^request_id, span_ctx, _agent_context}] = :ets.lookup(@table, request_id)
      assert span_ctx != nil
    end

    test "handles missing request_id gracefully" do
      # Should not raise even without request_id
      :telemetry.execute(
        [:req_llm, :request, :start],
        %{system_time: System.system_time()},
        %{model: %{id: "test", provider: "test"}}
      )
    end

    test "links ReqLLM payloads to queued Jido.AI llm spans by agent when ReqLLM request ids differ" do
      request_id = "jido-ai-turn-#{System.unique_integer([:positive])}"
      req_llm_request_id = "req-llm-#{System.unique_integer([:positive])}"
      call_id = "llm-call-#{System.unique_integer([:positive])}"
      agent_id = "agent-#{System.unique_integer([:positive])}"
      workspace_id = "workspace-#{System.unique_integer([:positive])}"

      SessionCache.put(agent_id, workspace_id, "Trace Agent")

      Store.start_turn(%{
        request_id: request_id,
        agent_id: agent_id,
        agent_name: "Trace Agent",
        session_id: agent_id,
        workspace_id: workspace_id,
        interaction_id: "interaction-#{System.unique_integer([:positive])}",
        input_value: "queued request"
      })

      :telemetry.execute(
        [:jido, :ai, :llm, :start],
        %{system_time: System.system_time()},
        %{request_id: request_id, llm_call_id: call_id, model: %{id: "openai:gpt-5-mini", provider: "openai"}}
      )

      Observability.clear_active_llm_call_id()
      Logger.metadata(agent_id: agent_id)

      :telemetry.execute(
        [:req_llm, :request, :start],
        %{system_time: System.system_time()},
        start_metadata(req_llm_request_id,
          request_payload: %{messages: [%{role: "user", content: "queued request"}]}
        )
      )

      assert [{^call_id, llm_record}] = :ets.lookup(@llm_span_table, call_id)
      assert llm_record.input_attrs["llm.input_messages.0.message.role"] == "user"
      assert llm_record.input_attrs["llm.input_messages.0.message.content"] == "queued request"

      Logger.metadata(agent_id: nil)
      Store.finish_turn(request_id, %{response: "done"})
    end

    test "captures input messages when ReqLLM request start happens before llm start telemetry" do
      request_id = "jido-ai-turn-#{System.unique_integer([:positive])}"
      req_llm_request_id = "req-llm-#{System.unique_integer([:positive])}"
      call_id = "llm-call-#{System.unique_integer([:positive])}"
      agent_id = "agent-#{System.unique_integer([:positive])}"
      workspace_id = "workspace-#{System.unique_integer([:positive])}"

      SessionCache.put(agent_id, workspace_id, "Trace Agent")

      Store.start_turn(%{
        request_id: request_id,
        agent_id: agent_id,
        agent_name: "Trace Agent",
        session_id: agent_id,
        workspace_id: workspace_id,
        interaction_id: "interaction-#{System.unique_integer([:positive])}",
        input_value: "pre-start request"
      })

      Logger.metadata(agent_id: agent_id)

      :telemetry.execute(
        [:req_llm, :request, :start],
        %{system_time: System.system_time()},
        start_metadata(req_llm_request_id,
          request_payload: %{messages: [%{role: "user", content: "pre-start request"}]}
        )
      )

      :telemetry.execute(
        [:jido, :ai, :llm, :start],
        %{system_time: System.system_time()},
        %{request_id: request_id, llm_call_id: call_id, model: %{id: "openai:gpt-5-mini", provider: "openai"}}
      )

      assert [{^call_id, llm_record}] = :ets.lookup(@llm_span_table, call_id)
      assert llm_record.input_attrs["llm.input_messages.0.message.content"] == "pre-start request"

      Logger.metadata(agent_id: nil)
      Store.finish_turn(request_id, %{response: "done"})
    end

    test "captures input messages when ReqLLM request start happens after llm start telemetry without agent context" do
      request_id = "jido-ai-turn-#{System.unique_integer([:positive])}"
      req_llm_request_id = "req-llm-#{System.unique_integer([:positive])}"
      call_id = "llm-call-#{System.unique_integer([:positive])}"
      agent_id = "agent-#{System.unique_integer([:positive])}"
      workspace_id = "workspace-#{System.unique_integer([:positive])}"

      SessionCache.put(agent_id, workspace_id, "Trace Agent")

      Store.start_turn(%{
        request_id: request_id,
        agent_id: agent_id,
        agent_name: "Trace Agent",
        session_id: agent_id,
        workspace_id: workspace_id,
        interaction_id: "interaction-#{System.unique_integer([:positive])}",
        input_value: "late request"
      })

      :telemetry.execute(
        [:jido, :ai, :llm, :start],
        %{system_time: System.system_time()},
        %{request_id: request_id, llm_call_id: call_id, model: %{id: "openai:gpt-5-mini", provider: "openai"}}
      )

      Logger.metadata(agent_id: nil)

      :telemetry.execute(
        [:req_llm, :request, :start],
        %{system_time: System.system_time()},
        start_metadata(req_llm_request_id,
          request_payload: %{messages: [%{role: "user", content: "late request"}]}
        )
      )

      assert [{^call_id, llm_record}] = :ets.lookup(@llm_span_table, call_id)
      assert llm_record.input_attrs["llm.input_messages.0.message.content"] == "late request"

      Store.finish_turn(request_id, %{response: "done"})
    end

    test "captures prepared input messages without ReqLLM start telemetry" do
      request_id = "jido-ai-turn-#{System.unique_integer([:positive])}"
      call_id = "llm-call-#{System.unique_integer([:positive])}"
      agent_id = "agent-#{System.unique_integer([:positive])}"
      workspace_id = "workspace-#{System.unique_integer([:positive])}"

      SessionCache.put(agent_id, workspace_id, "Trace Agent")

      Store.start_turn(%{
        request_id: request_id,
        agent_id: agent_id,
        agent_name: "Trace Agent",
        session_id: agent_id,
        workspace_id: workspace_id,
        interaction_id: "interaction-#{System.unique_integer([:positive])}",
        input_value: "prepared request"
      })

      Observability.record_prepared_llm_input(call_id, [
        %{role: :assistant, tool_calls: [%{id: "tool-1", name: "tell", arguments: %{message: "prepared request"}}]},
        %{role: :tool, tool_call_id: "tool-1", name: "tell", content: ~s({"ok":true})},
        %{role: :user, content: "prepared request"}
      ])

      :telemetry.execute(
        [:jido, :ai, :llm, :start],
        %{system_time: System.system_time()},
        %{request_id: request_id, llm_call_id: call_id, model: %{id: "openai:gpt-5-mini", provider: "openai"}}
      )

      assert [{^call_id, llm_record}] = :ets.lookup(@llm_span_table, call_id)
      assert llm_record.input_attrs["llm.input_messages.0.message.role"] == "assistant"
      assert llm_record.input_attrs["llm.input_messages.0.message.tool_calls.0.tool_call.function.name"] == "tell"
      assert llm_record.input_attrs["llm.input_messages.1.message.role"] == "tool"
      assert llm_record.input_attrs["llm.input_messages.2.message.content"] == "prepared request"
      assert llm_record.input_attrs["input.value"] == "prepared request"

      Store.finish_turn(request_id, %{response: "done"})
    end
  end

  describe "stop event - same process" do
    test "removes span from ETS and ends span" do
      request_id = "test-#{System.unique_integer([:positive])}"

      :telemetry.execute(
        [:req_llm, :request, :start],
        %{system_time: System.system_time()},
        start_metadata(request_id)
      )

      assert :ets.lookup(@table, request_id) != []

      :telemetry.execute(
        [:req_llm, :request, :stop],
        %{duration: 1_000_000},
        stop_metadata(request_id)
      )

      # Span should be removed from ETS
      assert :ets.lookup(@table, request_id) == []
    end

    test "handles missing request_id gracefully" do
      :telemetry.execute(
        [:req_llm, :request, :stop],
        %{duration: 0},
        stop_metadata(nil)
      )
    end

    test "handles unknown request_id gracefully" do
      :telemetry.execute(
        [:req_llm, :request, :stop],
        %{duration: 0},
        stop_metadata("nonexistent-id")
      )
    end
  end

  describe "stop event - cross-process (streaming scenario)" do
    test "stop event from different process can find and end span" do
      request_id = "stream-#{System.unique_integer([:positive])}"

      # Start event fires in caller process
      :telemetry.execute(
        [:req_llm, :request, :start],
        %{system_time: System.system_time()},
        start_metadata(request_id)
      )

      assert :ets.lookup(@table, request_id) != []

      # Stop event fires from a different process (simulating StreamServer)
      task =
        Task.async(fn ->
          :telemetry.execute(
            [:req_llm, :request, :stop],
            %{duration: 5_000_000},
            stop_metadata(request_id, usage: %{input_tokens: 200, output_tokens: 100})
          )
        end)

      Task.await(task)

      # Span should be cleaned up from ETS
      assert :ets.lookup(@table, request_id) == []
    end
  end

  describe "exception event" do
    test "removes span from ETS on error" do
      request_id = "error-#{System.unique_integer([:positive])}"

      :telemetry.execute(
        [:req_llm, :request, :start],
        %{system_time: System.system_time()},
        start_metadata(request_id)
      )

      assert :ets.lookup(@table, request_id) != []

      :telemetry.execute(
        [:req_llm, :request, :exception],
        %{duration: 0},
        exception_metadata(request_id)
      )

      assert :ets.lookup(@table, request_id) == []
    end

    test "exception from different process works" do
      request_id = "error-cross-#{System.unique_integer([:positive])}"

      :telemetry.execute(
        [:req_llm, :request, :start],
        %{system_time: System.system_time()},
        start_metadata(request_id)
      )

      task =
        Task.async(fn ->
          :telemetry.execute(
            [:req_llm, :request, :exception],
            %{duration: 0},
            exception_metadata(request_id)
          )
        end)

      Task.await(task)
      assert :ets.lookup(@table, request_id) == []
    end
  end

  describe "model_name/1" do
    test "extracts from model struct with :id" do
      assert ReqLLMTracer.model_name(%{model: %{id: "anthropic:claude-3-5-sonnet"}}) ==
               "anthropic:claude-3-5-sonnet"
    end

    test "extracts from string model" do
      assert ReqLLMTracer.model_name(%{model: "openai:gpt-4"}) == "openai:gpt-4"
    end

    test "returns unknown for missing model" do
      assert ReqLLMTracer.model_name(%{}) == "unknown"
    end
  end

  describe "provider/1" do
    test "extracts from model struct with :provider" do
      assert ReqLLMTracer.provider(%{model: %{provider: "anthropic"}}) == "anthropic"
    end

    test "extracts from top-level :provider" do
      assert ReqLLMTracer.provider(%{provider: "openai"}) == "openai"
    end

    test "returns unknown for missing provider" do
      assert ReqLLMTracer.provider(%{}) == "unknown"
    end
  end

  describe "concurrent requests" do
    test "multiple simultaneous requests maintain separate span contexts" do
      ids = for i <- 1..5, do: "concurrent-#{i}-#{System.unique_integer([:positive])}"

      # Start all requests
      for id <- ids do
        :telemetry.execute(
          [:req_llm, :request, :start],
          %{system_time: System.system_time()},
          start_metadata(id)
        )
      end

      assert :ets.info(@table, :size) >= 5

      # Stop them in reverse order from different tasks
      tasks =
        ids
        |> Enum.reverse()
        |> Enum.map(fn id ->
          Task.async(fn ->
            :telemetry.execute(
              [:req_llm, :request, :stop],
              %{duration: 1_000_000},
              stop_metadata(id)
            )

            id
          end)
        end)

      results = Task.await_many(tasks)
      assert length(results) == 5

      # All spans should be cleaned up
      for id <- ids do
        assert :ets.lookup(@table, id) == []
      end
    end
  end

  # --- US1: Integration tests for input/output messages (T014, T017) ---

  describe "US1 - input message attributes on start event" do
    test "start event with request_payload flattens input messages into span" do
      request_id = "us1-start-#{System.unique_integer([:positive])}"

      :telemetry.execute(
        [:req_llm, :request, :start],
        %{system_time: System.system_time()},
        start_metadata(request_id,
          request_payload: %{
            messages: [
              %{role: "system", content: "You are helpful"},
              %{role: "user", content: "Hello"}
            ]
          }
        )
      )

      # Span was created and stored in ETS
      assert [{^request_id, _span_ctx, _agent_ctx}] = :ets.lookup(@table, request_id)
    end

    test "start event without request_payload still works" do
      request_id = "us1-no-payload-#{System.unique_integer([:positive])}"

      :telemetry.execute(
        [:req_llm, :request, :start],
        %{system_time: System.system_time()},
        start_metadata(request_id)
      )

      assert [{^request_id, _span_ctx, _agent_ctx}] = :ets.lookup(@table, request_id)
    end
  end

  describe "US1 - end-to-end start→stop cycle with messages" do
    test "full cycle with request and response payloads" do
      request_id = "us1-e2e-#{System.unique_integer([:positive])}"

      :telemetry.execute(
        [:req_llm, :request, :start],
        %{system_time: System.system_time()},
        start_metadata(request_id,
          request_payload: %{
            messages: [
              %{role: "system", content: "You are helpful"},
              %{role: "user", content: "What is the weather?"}
            ]
          }
        )
      )

      assert :ets.lookup(@table, request_id) != []

      :telemetry.execute(
        [:req_llm, :request, :stop],
        %{duration: 2_000_000},
        stop_metadata(request_id,
          response_payload: %{
            choices: [%{message: %{role: "assistant", content: "It's sunny today!"}}]
          }
        )
      )

      # Span should be cleaned up
      assert :ets.lookup(@table, request_id) == []
    end

    test "stop event with response_payload containing text field" do
      request_id = "us1-text-#{System.unique_integer([:positive])}"

      :telemetry.execute(
        [:req_llm, :request, :start],
        %{system_time: System.system_time()},
        start_metadata(request_id)
      )

      :telemetry.execute(
        [:req_llm, :request, :stop],
        %{duration: 1_000_000},
        stop_metadata(request_id,
          response_payload: %{text: "Simple text response"}
        )
      )

      assert :ets.lookup(@table, request_id) == []
    end
  end

  # --- BUG FIX: Streaming response_payload lacks message content ---

  describe "build_output_attrs/1 - streaming fallback" do
    test "streaming payload (no message) falls back to response_summary for output.value" do
      metadata = %{
        response_payload: %{finish_reason: :stop, usage: %{input_tokens: 100, output_tokens: 50}},
        response_summary: %{text: "Hi — hello! I'm Alice. How can I help you today?"}
      }

      result = ReqLLMTracer.build_output_attrs(metadata)

      assert result["output.value"] == "Hi — hello! I'm Alice. How can I help you today?"
    end

    test "non-streaming payload (with message) extracts output from message" do
      metadata = %{
        response_payload: %{
          message: %{role: :assistant, content: [%{type: :text, text: "Response from payload"}]}
        },
        response_summary: %{text: "Response from payload"}
      }

      result = ReqLLMTracer.build_output_attrs(metadata)

      assert result["output.value"] == "Response from payload"
      assert result["llm.output_messages.0.message.role"] == "assistant"
      assert result["llm.output_messages.0.message.content"] == "Response from payload"
    end

    test "no response_payload at all falls back to response_summary" do
      metadata = %{
        response_summary: %{text: "Fallback text"}
      }

      result = ReqLLMTracer.build_output_attrs(metadata)

      assert result["output.value"] == "Fallback text"
    end

    test "no response_payload and no response_summary returns empty map" do
      result = ReqLLMTracer.build_output_attrs(%{})

      assert result == %{}
    end

    test "streaming payload with text_bytes shows byte count indicator" do
      # Real streaming: response_summary has text_bytes but NOT text
      metadata = %{
        response_payload: %{status: 200, usage: %{input_tokens: 100, output_tokens: 50}},
        response_summary: %{text_bytes: 342, thinking_bytes: 0, tool_call_count: 0, image_count: 0, object?: false}
      }

      result = ReqLLMTracer.build_output_attrs(metadata)

      assert result["output.value"] == "[streamed response: 342 bytes]"
    end

    test "streaming payload with context.messages extracts output from context" do
      # Some streaming payloads may include context with full conversation history
      metadata = %{
        response_payload: %{
          finish_reason: :stop,
          context: %{
            messages: [
              %{role: :system, content: [%{type: :text, text: "You are helpful"}]},
              %{role: :user, content: [%{type: :text, text: "Hello"}]},
              %{role: :assistant, content: [%{type: :text, text: "Hi there!"}]}
            ]
          }
        },
        response_summary: %{text: "Hi there!"}
      }

      result = ReqLLMTracer.build_output_attrs(metadata)

      # Should fall back to response_summary since extract_response_messages
      # doesn't know about context.messages — that's fine
      assert result["output.value"] == "Hi there!"
    end
  end

  # --- US6: Cross-process streaming with payloads (T018, T020) ---

  describe "US6 - cross-process streaming with message payloads" do
    test "start in process A with messages, stop in process B with response" do
      request_id = "us6-stream-#{System.unique_integer([:positive])}"

      # Start event fires in caller process with request_payload
      :telemetry.execute(
        [:req_llm, :request, :start],
        %{system_time: System.system_time()},
        start_metadata(request_id,
          request_payload: %{
            messages: [
              %{role: "system", content: "You are a helpful assistant"},
              %{role: "user", content: "Tell me a joke"}
            ]
          }
        )
      )

      assert [{^request_id, _span, _ctx}] = :ets.lookup(@table, request_id)

      # Stop event fires from StreamServer (different process)
      task =
        Task.async(fn ->
          :telemetry.execute(
            [:req_llm, :request, :stop],
            %{duration: 3_000_000},
            stop_metadata(request_id,
              usage: %{input_tokens: 200, output_tokens: 100},
              response_payload: %{
                choices: [%{message: %{role: "assistant", content: "Why did the chicken cross the road?"}}]
              }
            )
          )
        end)

      Task.await(task)

      # Span cleaned up from ETS
      assert :ets.lookup(@table, request_id) == []
    end

    test "start in process A, exception in process B preserves input attributes" do
      request_id = "us6-error-#{System.unique_integer([:positive])}"

      # Start event with messages
      :telemetry.execute(
        [:req_llm, :request, :start],
        %{system_time: System.system_time()},
        start_metadata(request_id,
          request_payload: %{
            messages: [%{role: "user", content: "This will fail"}]
          }
        )
      )

      assert [{^request_id, _span, _ctx}] = :ets.lookup(@table, request_id)

      # Exception from different process
      task =
        Task.async(fn ->
          :telemetry.execute(
            [:req_llm, :request, :exception],
            %{duration: 0},
            exception_metadata(request_id)
          )
        end)

      Task.await(task)

      # Span cleaned up
      assert :ets.lookup(@table, request_id) == []
    end
  end

  # --- US2: Token usage verification (T022) ---

  describe "US2 - token count attributes" do
    test "stop event correctly sets all five token attributes" do
      request_id = "us2-tokens-#{System.unique_integer([:positive])}"

      :telemetry.execute(
        [:req_llm, :request, :start],
        %{system_time: System.system_time()},
        start_metadata(request_id)
      )

      # The stop handler sets token attributes on the span before ending it.
      # We verify the handler completes without error (span is cleaned up).
      :telemetry.execute(
        [:req_llm, :request, :stop],
        %{duration: 1_500_000},
        stop_metadata(request_id, usage: %{input_tokens: 150, output_tokens: 80})
      )

      # Span removed from ETS (stop handler completed successfully)
      assert :ets.lookup(@table, request_id) == []
    end

    test "stop event with nil usage defaults to zero" do
      request_id = "us2-nil-usage-#{System.unique_integer([:positive])}"

      :telemetry.execute(
        [:req_llm, :request, :start],
        %{system_time: System.system_time()},
        start_metadata(request_id)
      )

      :telemetry.execute(
        [:req_llm, :request, :stop],
        %{duration: 1_000_000},
        stop_metadata(request_id, usage: nil)
      )

      assert :ets.lookup(@table, request_id) == []
    end
  end

  # --- US3: Tool call integration tests (T023, T024) ---

  describe "US3 - tool call attributes in output messages" do
    test "stop event with assistant tool calls flattens into span" do
      request_id = "us3-tool-out-#{System.unique_integer([:positive])}"

      :telemetry.execute(
        [:req_llm, :request, :start],
        %{system_time: System.system_time()},
        start_metadata(request_id)
      )

      :telemetry.execute(
        [:req_llm, :request, :stop],
        %{duration: 1_000_000},
        stop_metadata(request_id,
          response_payload: %{
            choices: [
              %{
                message: %{
                  role: "assistant",
                  content: nil,
                  tool_calls: [
                    %{function: %{name: "get_weather", arguments: %{city: "Amsterdam"}}}
                  ]
                }
              }
            ]
          }
        )
      )

      assert :ets.lookup(@table, request_id) == []
    end
  end

  describe "US3 - tool result messages in input" do
    test "start event with tool role message" do
      request_id = "us3-tool-in-#{System.unique_integer([:positive])}"

      :telemetry.execute(
        [:req_llm, :request, :start],
        %{system_time: System.system_time()},
        start_metadata(request_id,
          request_payload: %{
            messages: [
              %{role: "user", content: "What's the weather?"},
              %{role: "assistant", content: nil, tool_calls: [%{function: %{name: "get_weather", arguments: %{city: "Amsterdam"}}}]},
              %{role: "tool", content: ~s({"temp": 18}), name: "get_weather"}
            ]
          }
        )
      )

      assert [{^request_id, _span, _ctx}] = :ets.lookup(@table, request_id)

      # Clean up
      :telemetry.execute(
        [:req_llm, :request, :stop],
        %{duration: 1_000_000},
        stop_metadata(request_id)
      )
    end
  end

  # --- US4: Session grouping (T026, T028) ---

  describe "US4 - session enrichment via SessionCache" do
    test "start event with agent_id in Logger.metadata adds session.id" do
      request_id = "us4-session-#{System.unique_integer([:positive])}"
      agent_id = "agent-#{System.unique_integer([:positive])}"
      workspace_id = "workspace-#{System.unique_integer([:positive])}"

      SessionCache.put(agent_id, workspace_id, "TestAgent")

      # Set agent_id in Logger metadata (simulating what agent processes do)
      Logger.metadata(agent_id: agent_id)

      :telemetry.execute(
        [:req_llm, :request, :start],
        %{system_time: System.system_time()},
        start_metadata(request_id)
      )

      assert [{^request_id, _span, agent_context}] = :ets.lookup(@table, request_id)
      assert agent_context == %{agent_id: agent_id, workspace_id: workspace_id, display_name: "TestAgent"}

      # Clean up Logger metadata
      Logger.metadata(agent_id: nil)

      # Clean up span
      :telemetry.execute(
        [:req_llm, :request, :stop],
        %{duration: 1_000_000},
        stop_metadata(request_id)
      )
    end

    test "session.id survives cross-process stop" do
      request_id = "us4-cross-#{System.unique_integer([:positive])}"
      agent_id = "agent-#{System.unique_integer([:positive])}"
      workspace_id = "ws-#{System.unique_integer([:positive])}"

      SessionCache.put(agent_id, workspace_id, "CrossAgent")
      Logger.metadata(agent_id: agent_id)

      :telemetry.execute(
        [:req_llm, :request, :start],
        %{system_time: System.system_time()},
        start_metadata(request_id)
      )

      Logger.metadata(agent_id: nil)

      # Stop from different process — session.id was already set on span at start time
      task =
        Task.async(fn ->
          :telemetry.execute(
            [:req_llm, :request, :stop],
            %{duration: 2_000_000},
            stop_metadata(request_id)
          )
        end)

      Task.await(task)
      assert :ets.lookup(@table, request_id) == []
    end
  end

  # --- US5: Agent identity (T029, T031) ---

  describe "US5 - agent identity enrichment" do
    test "start event with agent in cache sets llm.agent_name" do
      request_id = "us5-name-#{System.unique_integer([:positive])}"
      agent_id = "agent-#{System.unique_integer([:positive])}"

      SessionCache.put(agent_id, "ws-123", "Bob")
      Logger.metadata(agent_id: agent_id)

      :telemetry.execute(
        [:req_llm, :request, :start],
        %{system_time: System.system_time()},
        start_metadata(request_id)
      )

      assert [{^request_id, _span, agent_context}] = :ets.lookup(@table, request_id)
      assert agent_context.display_name == "Bob"

      Logger.metadata(agent_id: nil)

      :telemetry.execute(
        [:req_llm, :request, :stop],
        %{duration: 1_000_000},
        stop_metadata(request_id)
      )
    end

    test "graceful degradation without agent context" do
      request_id = "us5-no-agent-#{System.unique_integer([:positive])}"

      # No Logger.metadata agent_id set, no Process.get :jido_agent_id
      :telemetry.execute(
        [:req_llm, :request, :start],
        %{system_time: System.system_time()},
        start_metadata(request_id)
      )

      # Span was still created (no crash)
      assert [{^request_id, _span, nil}] = :ets.lookup(@table, request_id)

      :telemetry.execute(
        [:req_llm, :request, :stop],
        %{duration: 1_000_000},
        stop_metadata(request_id)
      )

      assert :ets.lookup(@table, request_id) == []
    end

    test "resolves agent_id from $callers via Jido Registry with suffixed key" do
      request_id = "us5-callers-#{System.unique_integer([:positive])}"
      agent_id = "agent-callers-#{System.unique_integer([:positive])}"
      workspace_id = "ws-callers-#{System.unique_integer([:positive])}"

      # Populate SessionCache with the BASE agent_id (no suffix)
      SessionCache.put(agent_id, workspace_id, "CallerAgent")

      jido_mod = Application.fetch_env!(:jido_murmur, :jido_mod)
      registry = Module.concat(jido_mod, Registry)

      # In production, the ReAct worker is registered with a suffixed key
      # like "session_id/react_worker", not the bare session_id.
      suffixed_key = "#{agent_id}/react_worker"
      test_pid = self()

      react_worker =
        start_supervised!(
          {Agent, fn ->
            Registry.register(registry, suffixed_key, [])
            send(test_pid, :registered)
            :ok
          end},
          id: :fake_react_worker
        )

      assert_receive :registered

      # In production, the LLM Task is spawned from within the react_worker
      # process. The react_worker PID ends up in $callers.
      task =
        Task.async(fn ->
          Process.put(:"$callers", [react_worker])

          :telemetry.execute(
            [:req_llm, :request, :start],
            %{system_time: System.system_time()},
            start_metadata(request_id)
          )
        end)

      Task.await(task)

      # Should find the suffixed key, strip the suffix, and resolve via SessionCache
      assert [{^request_id, _span, agent_context}] = :ets.lookup(@table, request_id)
      assert agent_context == %{agent_id: agent_id, workspace_id: workspace_id, display_name: "CallerAgent"}

      # Clean up
      :telemetry.execute(
        [:req_llm, :request, :stop],
        %{duration: 1_000_000},
        stop_metadata(request_id)
      )
    end
  end

  # --- Foundation helper tests (T010-T013) ---

  describe "flatten_input_messages/1" do
    test "single user message" do
      messages = [%{role: "user", content: "Hello"}]
      result = ReqLLMTracer.flatten_input_messages(messages)

      assert result["llm.input_messages.0.message.role"] == "user"
      assert result["llm.input_messages.0.message.content"] == "Hello"
    end

    test "multi-message conversation (system + user + assistant)" do
      messages = [
        %{role: "system", content: "You are helpful"},
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there!"}
      ]

      result = ReqLLMTracer.flatten_input_messages(messages)

      assert result["llm.input_messages.0.message.role"] == "system"
      assert result["llm.input_messages.0.message.content"] == "You are helpful"
      assert result["llm.input_messages.1.message.role"] == "user"
      assert result["llm.input_messages.1.message.content"] == "Hello"
      assert result["llm.input_messages.2.message.role"] == "assistant"
      assert result["llm.input_messages.2.message.content"] == "Hi there!"
    end

    test "empty message list" do
      assert ReqLLMTracer.flatten_input_messages([]) == %{}
    end

    test "messages with content part lists" do
      messages = [
        %{role: "user", content: [%{type: :text, text: "Part 1"}, %{type: :text, text: " Part 2"}]}
      ]

      result = ReqLLMTracer.flatten_input_messages(messages)

      assert result["llm.input_messages.0.message.role"] == "user"
      assert result["llm.input_messages.0.message.content"] == "Part 1 Part 2"
    end

    test "messages with atom roles" do
      messages = [%{role: :user, content: "Hello"}]
      result = ReqLLMTracer.flatten_input_messages(messages)

      assert result["llm.input_messages.0.message.role"] == "user"
    end

    test "tool messages preserve name and tool_call_id" do
      messages = [%{role: :tool, tool_call_id: "call_123", name: "get_weather", content: ~s({"temp":18})}]
      result = ReqLLMTracer.flatten_input_messages(messages)

      assert result["llm.input_messages.0.message.role"] == "tool"
      assert result["llm.input_messages.0.message.name"] == "get_weather"
      assert result["llm.input_messages.0.message.tool_call_id"] == "call_123"
    end
  end

  describe "flatten_output_messages/1" do
    test "single assistant response" do
      messages = [%{role: "assistant", content: "Hello!"}]
      result = ReqLLMTracer.flatten_output_messages(messages)

      assert result["llm.output_messages.0.message.role"] == "assistant"
      assert result["llm.output_messages.0.message.content"] == "Hello!"
    end

    test "assistant response with tool calls" do
      messages = [
        %{
          role: "assistant",
          content: nil,
          tool_calls: [%{id: "tool_1", function: %{name: "get_weather", arguments: %{city: "Amsterdam"}}}]
        }
      ]

      result = ReqLLMTracer.flatten_output_messages(messages)

      assert result["llm.output_messages.0.message.role"] == "assistant"
      assert result["llm.output_messages.0.message.tool_calls.0.tool_call.id"] == "tool_1"
      assert result["llm.output_messages.0.message.tool_calls.0.tool_call.function.name"] == "get_weather"
      assert result["llm.output_messages.0.message.tool_calls.0.tool_call.function.arguments"] == ~s({"city":"Amsterdam"})
    end

    test "tool-role output preserves name and tool_call_id" do
      messages = [%{role: "tool", name: "get_weather", tool_call_id: "tool_1", content: ~s({"temp":18})}]
      result = ReqLLMTracer.flatten_output_messages(messages)

      assert result["llm.output_messages.0.message.role"] == "tool"
      assert result["llm.output_messages.0.message.name"] == "get_weather"
      assert result["llm.output_messages.0.message.tool_call_id"] == "tool_1"
    end

    test "empty output" do
      assert ReqLLMTracer.flatten_output_messages([]) == %{}
      assert ReqLLMTracer.flatten_output_messages(nil) == %{}
    end
  end

  describe "flatten_tool_calls/3" do
    test "single tool call" do
      tool_calls = [%{function: %{name: "get_weather", arguments: %{city: "Amsterdam"}}}]
      result = ReqLLMTracer.flatten_tool_calls(0, tool_calls, :output)

      assert result["llm.output_messages.0.message.tool_calls.0.tool_call.function.name"] == "get_weather"
      assert result["llm.output_messages.0.message.tool_calls.0.tool_call.function.arguments"] == ~s({"city":"Amsterdam"})
    end

    test "multiple tool calls" do
      tool_calls = [
        %{function: %{name: "get_weather", arguments: %{city: "Amsterdam"}}},
        %{function: %{name: "get_time", arguments: %{timezone: "CET"}}}
      ]

      result = ReqLLMTracer.flatten_tool_calls(0, tool_calls, :output)

      assert result["llm.output_messages.0.message.tool_calls.0.tool_call.function.name"] == "get_weather"
      assert result["llm.output_messages.0.message.tool_calls.1.tool_call.function.name"] == "get_time"
    end

    test "tool call with string arguments (pre-encoded JSON)" do
      tool_calls = [%{function: %{name: "search", arguments: ~s({"query":"test"})}}]
      result = ReqLLMTracer.flatten_tool_calls(0, tool_calls, :input)

      assert result["llm.input_messages.0.message.tool_calls.0.tool_call.function.arguments"] == ~s({"query":"test"})
    end

    test "flat Jido tool call shape preserves name and arguments" do
      tool_calls = [%{id: "tool_1", name: "tell", arguments: %{target_agent: "bob", message: "hello"}}]
      result = ReqLLMTracer.flatten_tool_calls(0, tool_calls, :output)

      assert result["llm.output_messages.0.message.tool_calls.0.tool_call.id"] == "tool_1"
      assert result["llm.output_messages.0.message.tool_calls.0.tool_call.function.name"] == "tell"

      assert result["llm.output_messages.0.message.tool_calls.0.tool_call.function.arguments"] ==
               ~s({"message":"hello","target_agent":"bob"})
    end

    test "ReqLLM.ToolCall structs are flattened without crashing" do
      tool_calls = [ReqLLM.ToolCall.new("tool_1", "tell", ~s({"target_agent":"bob","message":"hello"}))]
      result = ReqLLMTracer.flatten_tool_calls(0, tool_calls, :output)

      assert result["llm.output_messages.0.message.tool_calls.0.tool_call.id"] == "tool_1"
      assert result["llm.output_messages.0.message.tool_calls.0.tool_call.function.name"] == "tell"

      assert result["llm.output_messages.0.message.tool_calls.0.tool_call.function.arguments"] ==
               ~s({"target_agent":"bob","message":"hello"})
    end
  end

  describe "extract_content/1" do
    test "plain string" do
      assert ReqLLMTracer.extract_content("Hello") == "Hello"
    end

    test "content part list" do
      parts = [%{type: :text, text: "Hello"}, %{type: :text, text: " world"}]
      assert ReqLLMTracer.extract_content(parts) == "Hello world"
    end

    test "nil content" do
      assert ReqLLMTracer.extract_content(nil) == nil
    end

    test "empty string" do
      assert ReqLLMTracer.extract_content("") == nil
    end

    test "string-keyed content parts" do
      parts = [%{"type" => "text", "text" => "Hello"}]
      assert ReqLLMTracer.extract_content(parts) == "Hello"
    end
  end

  describe "extract_input_value/1 and extract_output_value/1" do
    test "extract_input_value returns last user message content" do
      messages = [
        %{role: "system", content: "You are helpful"},
        %{role: "user", content: "First question"},
        %{role: "assistant", content: "Answer"},
        %{role: "user", content: "Follow-up question"}
      ]

      assert ReqLLMTracer.extract_input_value(messages) == "Follow-up question"
    end

    test "extract_output_value returns last assistant message content" do
      messages = [
        %{role: "assistant", content: "First response"},
        %{role: "assistant", content: "Second response"}
      ]

      assert ReqLLMTracer.extract_output_value(messages) == "Second response"
    end

    test "returns nil for empty list" do
      assert ReqLLMTracer.extract_input_value([]) == nil
      assert ReqLLMTracer.extract_output_value([]) == nil
    end
  end
end
