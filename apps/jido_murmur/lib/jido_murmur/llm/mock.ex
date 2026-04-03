defmodule JidoMurmur.LLM.Mock do
  @moduledoc """
  Test LLM adapter with configurable canned responses.

  ## Usage

      # Set up a custom response for the current test process
      JidoMurmur.LLM.Mock.set_response(%{content: "Hello from mock!"})

      # The mock will return it on next await/3 call
  """
  @behaviour JidoMurmur.LLM

  alias JidoMurmur.Observability
  alias JidoMurmur.Observability.Tracer, as: ObservabilityTracer

  @default_response %{content: "Mock LLM response"}
  @default_model %{id: "openai:gpt-5-mini", provider: "openai"}
  @control_keys [
    :notify,
    :pause_after,
    :pause_ref,
    :stream_chunks,
    :tool_calls,
    :usage,
    :thinking_content,
    :model,
    :call_id,
    :duration_ms,
    :request_messages
  ]

  @impl true
  def ask(_agent_module, _pid, content, opts) do
    {:ok, %{content: content, opts: opts}}
  end

  @impl true
  def await(_agent_module, %{content: content, opts: opts}, _await_opts) do
    response = current_response()
    emit_observability(content, opts, response)
    {:ok, normalize_response(response)}
  end

  @doc "Set the mock response for the current process."
  def set_response(response) do
    Process.put(:mock_llm_response, response)
    Application.put_env(:jido_murmur, :mock_llm_response, response)
    :ok
  end

  def clear_response do
    Process.delete(:mock_llm_response)
    Application.delete_env(:jido_murmur, :mock_llm_response)
    :ok
  end

  defp current_response do
    Process.get(:mock_llm_response) ||
      Application.get_env(:jido_murmur, :mock_llm_response, @default_response)
  end

  defp normalize_response(%{} = response) do
    Map.drop(response, @control_keys)
  end

  defp normalize_response(response), do: response

  defp emit_observability(_content, _opts, response) when not is_map(response), do: :ok

  defp emit_observability(content, opts, response) do
    request_id = opts[:request_id]

    cond do
      not is_binary(request_id) ->
        :ok

      Application.get_env(:jido_murmur, :observability, [])[:enabled] == false ->
        :ok

      true ->
        do_emit_observability(content, opts, response)
    end
  end

  defp do_emit_observability(content, opts, response) do
    ctx = build_observability_context(content, opts, response)
    span_ctx = ObservabilityTracer.span_start([:jido, :ai, :llm, :span], ctx.metadata)

    emit_req_llm_start(ctx)
    notify(response, :started, %{request_id: ctx.request_id, call_id: ctx.call_id})
    maybe_pause(response, :start)

    emit_stream_deltas(ctx)
    notify(response, :deltas, %{request_id: ctx.request_id, call_id: ctx.call_id})
    maybe_pause(response, :deltas)

    emit_req_llm_stop(ctx)
    ObservabilityTracer.span_stop(span_ctx, %{duration_ms: ctx.duration_ms})
    emit_completion_signals(ctx)
    notify(response, :completed, %{request_id: ctx.request_id, call_id: ctx.call_id})
  end

  defp request_messages(content, response) do
    response[:request_messages] || [%{role: "user", content: content}]
  end

  defp build_observability_context(content, opts, response) do
    request_id = opts[:request_id]
    call_id = response[:call_id] || "mock_call_#{System.unique_integer([:positive])}"
    model = response[:model] || @default_model
    provider = model[:provider] || model["provider"] || "openai"
    usage = response[:usage] || %{input_tokens: 12, output_tokens: 8, total_tokens: 20}
    tool_calls = response[:tool_calls] || []
    assistant_text = Map.get(response, :content, @default_response.content)

    %{
      request_id: request_id,
      call_id: call_id,
      model: model,
      provider: provider,
      usage: usage,
      tool_calls: tool_calls,
      thinking_content: response[:thinking_content],
      assistant_text: assistant_text,
      chunks: response[:stream_chunks] || [assistant_text],
      duration_ms: Map.get(response, :duration_ms, 25),
      request_messages: request_messages(content, response),
      metadata: %{
        request_id: request_id,
        llm_call_id: call_id,
        tool_call_id: nil,
        model: model,
        provider: provider
      }
    }
  end

  defp emit_req_llm_start(ctx) do
    :telemetry.execute(
      [:req_llm, :request, :start],
      %{system_time: System.system_time()},
      %{
        request_id: ctx.request_id,
        model: ctx.model,
        provider: ctx.provider,
        request_payload: %{messages: ctx.request_messages}
      }
    )
  end

  defp emit_stream_deltas(ctx) do
    Enum.each(ctx.chunks, fn chunk ->
      Observability.record_signal(
        %{type: "ai.llm.delta", data: %{call_id: ctx.call_id, delta: chunk, chunk_type: :content}},
        %{}
      )
    end)
  end

  defp emit_req_llm_stop(ctx) do
    :telemetry.execute(
      [:req_llm, :request, :stop],
      %{duration: System.convert_time_unit(ctx.duration_ms, :millisecond, :native)},
      %{
        request_id: ctx.request_id,
        model: ctx.model,
        provider: ctx.provider,
        usage: ctx.usage,
        finish_reason: :stop,
        response_summary: %{text_bytes: byte_size(ctx.assistant_text || "")},
        response_payload: %{choices: [%{message: assistant_message(ctx)}]}
      }
    )
  end

  defp emit_completion_signals(ctx) do
    Observability.record_signal(
      %{type: "ai.usage", data: Map.merge(%{call_id: ctx.call_id, model: ctx.model.id}, ctx.usage)},
      %{}
    )

    Observability.record_signal(
      %{
        type: "ai.llm.response",
        data: %{
          call_id: ctx.call_id,
          usage: ctx.usage,
          result: {:ok, llm_result(ctx), []}
        }
      },
      %{}
    )
  end

  defp assistant_message(ctx) do
    %{role: "assistant", content: ctx.assistant_text, tool_calls: ctx.tool_calls}
  end

  defp llm_result(ctx) do
    %{
      type: if(ctx.tool_calls == [], do: :final_answer, else: :tool_calls),
      text: ctx.assistant_text,
      thinking_content: ctx.thinking_content,
      tool_calls: ctx.tool_calls,
      usage: ctx.usage
    }
  end

  defp notify(%{notify: pid}, phase, payload) when is_pid(pid) do
    send(pid, {:mock_llm_phase, phase, Map.put(payload, :waiter_pid, self())})
  end

  defp notify(_response, _phase, _payload), do: :ok

  defp maybe_pause(%{pause_after: phase, pause_ref: pause_ref}, phase) do
    receive do
      {:release_mock_llm, ^pause_ref} -> :ok
    after
      5_000 -> raise "Timed out waiting to release mock LLM at #{inspect(phase)}"
    end
  end

  defp maybe_pause(_response, _phase), do: :ok
end
