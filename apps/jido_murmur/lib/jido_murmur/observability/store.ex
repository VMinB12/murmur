defmodule JidoMurmur.Observability.Store do
  @moduledoc false

  require OpenTelemetry.Tracer, as: Tracer

  alias Jido.AI.Turn
  alias JidoMurmur.Observability
  alias JidoMurmur.Telemetry.ReqLLMTracer
  alias OpenTelemetry.{Ctx, Span}

  @turn_table :jido_murmur_obs_turns
  @agent_turn_table :jido_murmur_obs_agent_turns
  @llm_span_table :jido_murmur_obs_llm_spans
  @tool_span_table :jido_murmur_obs_tool_spans
  @tool_input_table :jido_murmur_obs_tool_inputs
  @req_llm_lookup_table :jido_murmur_obs_req_llm_lookup
  @pending_llm_call_table :jido_murmur_obs_pending_llm_calls
  @pending_agent_llm_call_table :jido_murmur_obs_pending_agent_llm_calls
  @pending_global_llm_call_table :jido_murmur_obs_pending_global_llm_calls
  @prepared_llm_input_table :jido_murmur_obs_prepared_llm_inputs
  @pending_req_llm_start_table :jido_murmur_obs_pending_req_llm_starts

  def create_tables do
    [
      @turn_table,
      @agent_turn_table,
      @llm_span_table,
      @tool_span_table,
      @tool_input_table,
      @req_llm_lookup_table,
      @pending_llm_call_table,
      @pending_agent_llm_call_table,
      @pending_global_llm_call_table,
      @prepared_llm_input_table,
      @pending_req_llm_start_table
    ]
    |> Enum.each(&ensure_table/1)
  end

  def record_prepared_llm_input(call_id, messages) when is_binary(call_id) and is_list(messages) do
    :ets.insert(@prepared_llm_input_table, {call_id, messages})
    apply_prepared_llm_input(call_id)
    :ok
  end

  def record_prepared_llm_input(_call_id, _messages), do: :ok

  def start_turn(attrs) do
    turn = build_turn(attrs)
    span_ctx = Tracer.start_span(turn_span_name(turn), %{attributes: turn_start_attrs(turn)})
    stored = Map.put(turn, :span_ctx, span_ctx)
    :ets.insert(@turn_table, {turn.request_id, stored})
    :ets.insert(@agent_turn_table, {turn.agent_id, turn.request_id})

    :ok
  end

  def finish_turn(request_id, attrs) do
    with {:ok, turn} <- fetch_turn(request_id) do
      response = Map.get(attrs, :response)

      span_attrs =
        %{"murmur.injected_message_count" => Map.get(turn, :injected_message_count, 0)}
        |> maybe_put("output.value", format_output(response), Observability.capture_content?())

      Span.set_attributes(turn.span_ctx, span_attrs)

      Span.end_span(turn.span_ctx)
      cleanup_turn(turn)
    end

    :ok
  end

  def fail_turn(request_id, reason, attrs \\ %{}) do
    with {:ok, turn} <- fetch_turn(request_id) do
      span_attrs =
        %{"murmur.injected_message_count" => Map.get(turn, :injected_message_count, 0)}
        |> Map.merge(Map.new(attrs, fn {key, value} -> {to_string(key), value} end))
        |> Map.put("error", true)
        |> Map.put("error.message", inspect(reason))

      Span.set_attributes(turn.span_ctx, span_attrs)

      Span.set_status(turn.span_ctx, OpenTelemetry.status(:error, inspect(reason)))
      Span.end_span(turn.span_ctx)
      cleanup_turn(turn)
    end

    :ok
  end

  def start_llm_span(metadata) do
    case metadata[:llm_call_id] do
      call_id when is_binary(call_id) ->
        turn = metadata[:request_id] |> lookup_turn() |> elem_or_nil(1)

        span_ctx =
          Tracer.start_span(parent_ctx(turn), llm_span_name(metadata),
            attributes: llm_start_attrs(metadata, turn)
          )

        record = %{
          call_id: call_id,
          request_id: metadata[:request_id],
          span_ctx: span_ctx,
          metadata: metadata,
          duration_ms: nil,
          usage: %{},
          streamed_text: "",
          streamed_thinking: "",
          finish_reason: nil,
          fallback_output_attrs: %{},
          error: nil,
          completed?: false
        }

        :ets.insert(@llm_span_table, {call_id, record})
    enqueue_pending_llm_call(metadata[:request_id], call_id)
    enqueue_pending_agent_llm_call(turn, call_id)
    enqueue_pending_global_llm_call(call_id)
        apply_prepared_llm_input(call_id)
    adopt_pending_req_llm_start(call_id, turn)
        %{kind: :llm, call_id: call_id}

      _ ->
        nil
    end
  end

  def start_tool_span(metadata) do
    case metadata[:tool_call_id] do
      call_id when is_binary(call_id) ->
        turn = metadata[:request_id] |> lookup_turn() |> elem_or_nil(1)

        span_ctx =
          Tracer.start_span(parent_ctx(turn), tool_span_name(metadata),
            attributes: tool_start_attrs(metadata, turn)
          )

        record = %{
          call_id: call_id,
          request_id: metadata[:request_id],
          span_ctx: span_ctx,
          metadata: metadata,
          duration_ms: nil,
          error: nil,
          completed?: false
        }

        :ets.insert(@tool_span_table, {call_id, record})
        %{kind: :tool, call_id: call_id}

      _ ->
        nil
    end
  end

  def mark_llm_span_complete(call_id, measurements) do
    update_span(@llm_span_table, call_id, fn record ->
      %{record | duration_ms: duration_ms(measurements), completed?: true}
    end)

    :ok
  end

  def mark_llm_span_error(call_id, kind, reason) do
    update_span(@llm_span_table, call_id, fn record ->
      %{record | error: %{kind: kind, reason: reason}, completed?: true}
    end)

    :ok
  end

  def mark_tool_span_complete(call_id, measurements) do
    update_span(@tool_span_table, call_id, fn record ->
      %{record | duration_ms: duration_ms(measurements), completed?: true}
    end)

    :ok
  end

  def mark_tool_span_error(call_id, kind, reason) do
    update_span(@tool_span_table, call_id, fn record ->
      %{record | error: %{kind: kind, reason: reason}, completed?: true}
    end)

    :ok
  end

  def record_req_llm_start(metadata, agent_context \\ nil) do
    with request_id when is_binary(request_id) <- metadata[:request_id],
         call_id when is_binary(call_id) <- bind_req_llm_call(request_id, agent_context) do
      apply_req_llm_start_to_call(call_id, metadata)

    else
      _ ->
        enqueue_pending_req_llm_start(agent_context, metadata)
    end

    :ok
  end

  def record_req_llm_stop(_measurements, metadata) do
    with request_id when is_binary(request_id) <- metadata[:request_id],
         call_id when is_binary(call_id) <- lookup_req_llm_call(request_id) do
      attrs =
        ReqLLMTracer.build_output_attrs(metadata)
        |> Map.drop(["output.value"])

      update_span(@llm_span_table, call_id, fn record ->
        record
        |> Map.put(:finish_reason, metadata[:finish_reason])
        |> Map.put(:fallback_output_attrs, attrs)
      end)
    end

    :ok
  end

  def record_req_llm_exception(metadata) do
    with request_id when is_binary(request_id) <- metadata[:request_id],
         call_id when is_binary(call_id) <- lookup_req_llm_call(request_id) do
      update_span(@llm_span_table, call_id, fn record ->
        %{record | error: %{kind: :error, reason: metadata[:error]}, completed?: true}
      end)

      :ets.delete(@req_llm_lookup_table, request_id)
    end

    :ok
  end

  def record_signal(%{type: "ai.llm.delta", data: data}, _context) do
    record_delta(data)
  end

  def record_signal(%{type: "ai.usage", data: data}, _context) do
    record_usage(data)
  end

  def record_signal(%{type: "ai.tool.started", data: data}, _context) do
    record_tool_started(data)
  end

  def record_signal(%{type: "ai.llm.response", data: data}, _context) do
    complete_llm_span(data)
  end

  def record_signal(%{type: "ai.tool.result", data: data}, _context) do
    complete_tool_span(data)
  end

  def record_signal(_signal, _context), do: :ok

  def record_injected_messages(agent_id, envelopes) when is_list(envelopes) do
    with [{^agent_id, request_id}] <- :ets.lookup(@agent_turn_table, agent_id),
         {:ok, turn} <- fetch_turn(request_id) do
      Enum.each(envelopes, fn envelope ->
        attrs =
          %{
            "murmur.message.kind" => to_string(Map.get(envelope, :kind, :direct)),
            "murmur.interaction_id" => Map.get(envelope, :interaction_id, "")
          }
          |> maybe_put("murmur.sender_name", Map.get(envelope, :sender_name))
          |> maybe_put("murmur.sender_trace_id", Map.get(envelope, :sender_trace_id))
          |> maybe_put("murmur.message.content", Map.get(envelope, :content), Observability.capture_content?())

        Span.add_event(turn.span_ctx, "murmur.injected_message", attrs)
      end)

      update_turn(request_id, fn current ->
        %{current | injected_message_count: Map.get(current, :injected_message_count, 0) + length(envelopes)}
      end)
    end

    :ok
  end

  defp record_delta(%{call_id: call_id, delta: delta, chunk_type: chunk_type}) when is_binary(call_id) do
    update_span(@llm_span_table, call_id, fn record ->
      case chunk_type do
        :thinking -> %{record | streamed_thinking: record.streamed_thinking <> delta}
        _ -> %{record | streamed_text: record.streamed_text <> delta}
      end
    end)
  end

  defp record_delta(_), do: :ok

  defp record_usage(%{call_id: call_id} = data) when is_binary(call_id) do
    usage = %{
      input_tokens: Map.get(data, :input_tokens, 0),
      output_tokens: Map.get(data, :output_tokens, 0),
      total_tokens: Map.get(data, :total_tokens, 0)
    }

    update_span(@llm_span_table, call_id, fn record -> %{record | usage: usage} end)
  end

  defp record_usage(_), do: :ok

  defp record_tool_started(%{call_id: call_id} = data) when is_binary(call_id) do
    info = %{id: call_id, name: Map.get(data, :tool_name), arguments: Map.get(data, :arguments)}
    :ets.insert(@tool_input_table, {call_id, info})

    with {:ok, record} <- fetch_span(@tool_span_table, call_id) do
      attrs =
        %{}
        |> maybe_put("tool.name", info.name)
        |> maybe_put("input.value", encode_input(info), Observability.capture_content?())

      Span.set_attributes(record.span_ctx, attrs)
    end

    :ok
  end

  defp record_tool_started(_), do: :ok

  defp complete_llm_span(%{call_id: call_id, result: result} = data) when is_binary(call_id) do
    with {:ok, record} <- fetch_span(@llm_span_table, call_id) do
      case result do
        {:ok, turn} -> finalize_llm_success(record, turn, data)
        {:ok, turn, _effects} -> finalize_llm_success(record, turn, data)
        {:error, reason} -> finalize_llm_error(record, reason)
        {:error, reason, _effects} -> finalize_llm_error(record, reason)
        other -> finalize_llm_error(record, other)
      end

      :ets.delete(@req_llm_lookup_table, record.request_id)
      delete_span(@llm_span_table, call_id)
    end

    :ok
  end

  defp complete_llm_span(_), do: :ok

  defp finalize_llm_success(record, turnish, data) do
    turn = Turn.from_result_map(turnish)
    usage = normalize_usage(Map.get(data, :usage) || turn.usage || record.usage)
    output_text = pick_output_text(turn, record)

    output_message = %{
      role: "assistant",
      content: output_text,
      tool_calls: turn.tool_calls
    }

    attrs =
      %{}
      |> Map.merge(Map.get(record, :input_attrs, %{}))
      |> Map.merge(Map.get(record, :fallback_output_attrs, %{}))
      |> Map.merge(ReqLLMTracer.flatten_output_messages([output_message]))
      |> maybe_put("output.value", output_text, Observability.capture_content?())
      |> maybe_put("murmur.llm.thinking_content", pick_thinking_text(turn, record), Observability.capture_content?())
      |> maybe_put("gen_ai.response.finish_reasons", finish_reason_string(record.finish_reason))
      |> maybe_put("llm.latency_ms", record.duration_ms)
      |> Map.merge(usage_attrs(usage))

    maybe_store_tool_inputs(turn.tool_calls)
    Span.set_attributes(record.span_ctx, attrs)
    Span.end_span(record.span_ctx)
  end

  defp finalize_llm_error(record, reason) do
    attrs =
      %{}
      |> Map.merge(Map.get(record, :input_attrs, %{}))
      |> maybe_put("llm.latency_ms", record.duration_ms)
      |> Map.put("error", true)
      |> Map.put("error.message", inspect(reason))

    Span.set_attributes(record.span_ctx, attrs)
    Span.set_status(record.span_ctx, OpenTelemetry.status(:error, inspect(reason)))
    Span.end_span(record.span_ctx)
  end

  defp complete_tool_span(%{call_id: call_id, result: result}) when is_binary(call_id) do
    with {:ok, record} <- fetch_span(@tool_span_table, call_id) do
      input_info = lookup_tool_input(call_id)

      attrs =
        %{}
        |> maybe_put("input.value", encode_input(input_info), Observability.capture_content?())
        |> maybe_put("output.value", Turn.format_tool_result_content(result), Observability.capture_content?())
        |> maybe_put("llm.latency_ms", record.duration_ms)

      case result do
        {:ok, _res} ->
          Span.set_attributes(record.span_ctx, attrs)

        {:ok, _res, _effects} ->
          Span.set_attributes(record.span_ctx, attrs)

        {:error, reason} ->
          Span.set_attributes(record.span_ctx, Map.put(attrs, "error.message", inspect(reason)) |> Map.put("error", true))
          Span.set_status(record.span_ctx, OpenTelemetry.status(:error, inspect(reason)))

        {:error, reason, _effects} ->
          Span.set_attributes(record.span_ctx, Map.put(attrs, "error.message", inspect(reason)) |> Map.put("error", true))
          Span.set_status(record.span_ctx, OpenTelemetry.status(:error, inspect(reason)))
      end

      Span.end_span(record.span_ctx)
      :ets.delete(@tool_input_table, call_id)
      delete_span(@tool_span_table, call_id)
    end

    :ok
  end

  defp complete_tool_span(_), do: :ok

  defp build_turn(attrs) do
    %{
      request_id: Map.fetch!(attrs, :request_id),
      agent_id: Map.fetch!(attrs, :agent_id),
      agent_name: Map.fetch!(attrs, :agent_name),
      session_id: Map.fetch!(attrs, :session_id),
      workspace_id: Map.fetch!(attrs, :workspace_id),
      interaction_id: Map.fetch!(attrs, :interaction_id),
      input_value: Map.fetch!(attrs, :input_value),
      message_count: Map.get(attrs, :message_count, 1),
      triggered_by_trace_id: Map.get(attrs, :triggered_by_trace_id),
      sender_name: Map.get(attrs, :sender_name),
      injected_message_count: 0
    }
  end

  defp turn_start_attrs(turn) do
    %{
      "openinference.span.kind" => "AGENT",
      "session.id" => turn.session_id,
      "murmur.agent_id" => turn.agent_id,
      "murmur.agent_name" => turn.agent_name,
      "murmur.workspace_id" => turn.workspace_id,
      "murmur.request_id" => turn.request_id,
      "murmur.interaction_id" => turn.interaction_id,
      "murmur.message_count" => turn.message_count
    }
    |> maybe_put("input.value", turn.input_value, Observability.capture_content?())
    |> maybe_put("murmur.triggered_by_trace_id", turn.triggered_by_trace_id)
    |> maybe_put("murmur.sender_name", turn.sender_name)
  end

  defp llm_start_attrs(metadata, turn) do
    model_name = ReqLLMTracer.model_name(metadata)
    provider = ReqLLMTracer.provider(metadata)
    system = ReqLLMTracer.system(metadata)

    %{
      "openinference.span.kind" => "LLM",
      "llm.model_name" => model_name,
      "llm.provider" => provider,
      "llm.system" => system,
      "gen_ai.system" => ReqLLMTracer.provider(metadata),
      "gen_ai.request.model" => model_name,
      "session.id" => turn && turn.session_id,
      "murmur.agent_id" => turn && turn.agent_id,
      "murmur.agent_name" => turn && turn.agent_name,
      "murmur.workspace_id" => turn && turn.workspace_id,
      "murmur.request_id" => metadata[:request_id],
      "murmur.interaction_id" => turn && turn.interaction_id,
      "murmur.llm_call_id" => metadata[:llm_call_id]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp tool_start_attrs(metadata, turn) do
    input_info = lookup_tool_input(metadata[:tool_call_id])

    %{
      "openinference.span.kind" => "TOOL",
      "tool.name" => metadata[:tool_name] || (input_info && input_info.name),
      "session.id" => turn && turn.session_id,
      "murmur.agent_id" => turn && turn.agent_id,
      "murmur.agent_name" => turn && turn.agent_name,
      "murmur.workspace_id" => turn && turn.workspace_id,
      "murmur.request_id" => metadata[:request_id],
      "murmur.interaction_id" => turn && turn.interaction_id,
      "murmur.tool_call_id" => metadata[:tool_call_id]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp turn_span_name(turn), do: "Agent #{turn.agent_name} turn"
  defp llm_span_name(metadata), do: "LLM #{ReqLLMTracer.model_name(metadata)}"
  defp tool_span_name(metadata), do: "Tool #{metadata[:tool_name] || metadata[:tool_call_id]}"

  defp parent_ctx(nil), do: Ctx.get_current()

  defp parent_ctx(%{span_ctx: span_ctx}) do
    OpenTelemetry.Tracer.set_current_span(Ctx.new(), span_ctx)
  end

  defp lookup_turn(request_id) when is_binary(request_id), do: List.first(:ets.lookup(@turn_table, request_id))
  defp lookup_turn(_), do: nil

  defp fetch_turn(request_id) do
    case :ets.lookup(@turn_table, request_id) do
      [{^request_id, turn}] -> {:ok, turn}
      [] -> :error
    end
  end

  defp fetch_span(table, key) do
    case :ets.lookup(table, key) do
      [{^key, record}] -> {:ok, record}
      [] -> :error
    end
  end

  defp delete_span(table, key), do: :ets.delete(table, key)

  defp cleanup_turn(turn) do
    :ets.delete(@turn_table, turn.request_id)
    :ets.delete(@agent_turn_table, turn.agent_id)
    :ets.delete(@req_llm_lookup_table, turn.request_id)
    :ets.delete(@pending_llm_call_table, turn.request_id)
    :ets.delete(@pending_agent_llm_call_table, turn.agent_id)
  end

  defp update_turn(request_id, fun) do
    update_span(@turn_table, request_id, fun)
  end

  defp update_span(table, key, fun) do
    case :ets.lookup(table, key) do
      [{^key, record}] -> :ets.insert(table, {key, fun.(record)})
      [] -> :ok
    end
  end

  defp apply_req_llm_start_to_call(call_id, metadata) do
    request_payload_messages(metadata)
    |> input_attrs_for_messages()
    |> merge_input_attrs(call_id)
  end

  defp apply_prepared_llm_input(call_id) when is_binary(call_id) do
    case :ets.lookup(@prepared_llm_input_table, call_id) do
      [{^call_id, messages}] when is_list(messages) ->
        maybe_apply_prepared_llm_input(call_id, messages)

      _ ->
        :ok
    end
  end

  defp maybe_apply_prepared_llm_input(call_id, messages) do
    if span_exists?(call_id) do
      messages
      |> input_attrs_for_messages()
      |> merge_input_attrs(call_id, :prepared)

      :ets.delete(@prepared_llm_input_table, call_id)
    else
      :ok
    end
  end

  defp span_exists?(call_id) do
    match?([{^call_id, _record}], :ets.lookup(@llm_span_table, call_id))
  end

  defp input_attrs_for_messages(messages) when is_list(messages) and messages != [] do
    ReqLLMTracer.flatten_input_messages(messages)
    |> maybe_put("input.value", ReqLLMTracer.extract_input_value(messages), Observability.capture_content?())
  end

  defp input_attrs_for_messages(_messages), do: %{}

  defp merge_input_attrs(input_attrs, call_id, merge_order \\ :req_llm)

  defp merge_input_attrs(input_attrs, _call_id, _merge_order) when input_attrs == %{}, do: :ok

  defp merge_input_attrs(input_attrs, call_id, :req_llm) do
    update_span(@llm_span_table, call_id, fn record ->
      Map.update(record, :input_attrs, input_attrs, &Map.merge(&1, input_attrs))
    end)
  end

  defp merge_input_attrs(input_attrs, call_id, :prepared) do
    update_span(@llm_span_table, call_id, fn record ->
      Map.update(record, :input_attrs, input_attrs, &Map.merge(input_attrs, &1))
    end)
  end

  defp ensure_table(table) do
    if :ets.whereis(table) == :undefined do
      :ets.new(table, [:named_table, :public, :set, read_concurrency: true])
    else
      table
    end
  end

  defp usage_attrs(nil), do: %{}

  defp usage_attrs(usage) do
    %{
      "llm.token_count.prompt" => Map.get(usage, :input_tokens, 0),
      "llm.token_count.completion" => Map.get(usage, :output_tokens, 0),
      "llm.token_count.total" => Map.get(usage, :total_tokens, 0),
      "gen_ai.usage.input_tokens" => Map.get(usage, :input_tokens, 0),
      "gen_ai.usage.output_tokens" => Map.get(usage, :output_tokens, 0)
    }
  end

  defp maybe_store_tool_inputs(tool_calls) when is_list(tool_calls) do
    Enum.each(tool_calls, fn tool_call ->
      if is_binary(tool_call[:id]) do
        :ets.insert(
          @tool_input_table,
          {tool_call[:id], %{id: tool_call[:id], name: tool_call[:name], arguments: tool_call[:arguments]}}
        )
      end
    end)
  end

  defp lookup_tool_input(nil), do: nil

  defp lookup_tool_input(call_id) do
    case :ets.lookup(@tool_input_table, call_id) do
      [{^call_id, info}] -> info
      [] -> nil
    end
  end

  defp lookup_req_llm_call(request_id) do
    case :ets.lookup(@req_llm_lookup_table, request_id) do
      [{^request_id, call_id}] -> call_id
      [] -> nil
    end
  end

  defp enqueue_pending_llm_call(request_id, call_id)
       when is_binary(request_id) and is_binary(call_id) do
    pending =
      case :ets.lookup(@pending_llm_call_table, request_id) do
        [{^request_id, call_ids}] -> call_ids
        [] -> []
      end

    :ets.insert(@pending_llm_call_table, {request_id, pending ++ [call_id]})
  end

  defp enqueue_pending_llm_call(_request_id, _call_id), do: :ok

  defp enqueue_pending_agent_llm_call(%{agent_id: agent_id}, call_id)
       when is_binary(agent_id) and is_binary(call_id) do
    pending =
      case :ets.lookup(@pending_agent_llm_call_table, agent_id) do
        [{^agent_id, call_ids}] -> call_ids
        [] -> []
      end

    :ets.insert(@pending_agent_llm_call_table, {agent_id, pending ++ [call_id]})
  end

  defp enqueue_pending_agent_llm_call(_turn, _call_id), do: :ok

  defp enqueue_pending_global_llm_call(call_id) when is_binary(call_id) do
    pending =
      case :ets.lookup(@pending_global_llm_call_table, :queue) do
        [{:queue, call_ids}] -> call_ids
        [] -> []
      end

    :ets.insert(@pending_global_llm_call_table, {:queue, pending ++ [call_id]})
  end

  defp bind_req_llm_call(request_id, agent_context) do
    call_id =
      normalize_call_id(Observability.current_active_llm_call_id()) ||
        pop_pending_llm_call(request_id) ||
        pop_pending_agent_llm_call(agent_context) ||
        pop_pending_global_llm_call() ||
        lookup_req_llm_call(request_id)

    if is_binary(call_id) do
      :ets.insert(@req_llm_lookup_table, {request_id, call_id})
      drop_pending_llm_call(request_id, call_id)
      drop_pending_agent_llm_call(agent_context, call_id)
      drop_pending_global_llm_call(call_id)
    end

    call_id
  end

  defp normalize_call_id(call_id) when is_binary(call_id), do: call_id
  defp normalize_call_id(_call_id), do: nil

  defp pop_pending_llm_call(request_id) do
    case :ets.lookup(@pending_llm_call_table, request_id) do
      [{^request_id, [call_id | rest]}] ->
        if rest == [] do
          :ets.delete(@pending_llm_call_table, request_id)
        else
          :ets.insert(@pending_llm_call_table, {request_id, rest})
        end

        call_id

      _ ->
        nil
    end
  end

  defp drop_pending_llm_call(request_id, call_id) do
    case :ets.lookup(@pending_llm_call_table, request_id) do
      [{^request_id, call_ids}] ->
        remaining = List.delete(call_ids, call_id)

        if remaining == [] do
          :ets.delete(@pending_llm_call_table, request_id)
        else
          :ets.insert(@pending_llm_call_table, {request_id, remaining})
        end

      [] ->
        :ok
    end
  end

  defp pop_pending_agent_llm_call(%{agent_id: agent_id}) when is_binary(agent_id) do
    case :ets.lookup(@pending_agent_llm_call_table, agent_id) do
      [{^agent_id, [call_id | rest]}] ->
        if rest == [] do
          :ets.delete(@pending_agent_llm_call_table, agent_id)
        else
          :ets.insert(@pending_agent_llm_call_table, {agent_id, rest})
        end

        call_id

      _ ->
        nil
    end
  end

  defp pop_pending_agent_llm_call(_agent_context), do: nil

  defp drop_pending_agent_llm_call(%{agent_id: agent_id}, call_id) when is_binary(agent_id) do
    case :ets.lookup(@pending_agent_llm_call_table, agent_id) do
      [{^agent_id, call_ids}] ->
        remaining = List.delete(call_ids, call_id)

        if remaining == [] do
          :ets.delete(@pending_agent_llm_call_table, agent_id)
        else
          :ets.insert(@pending_agent_llm_call_table, {agent_id, remaining})
        end

      [] ->
        :ok
    end
  end

  defp drop_pending_agent_llm_call(_agent_context, _call_id), do: :ok

  defp pop_pending_global_llm_call do
    case :ets.lookup(@pending_global_llm_call_table, :queue) do
      [{:queue, [call_id | rest]}] ->
        if rest == [] do
          :ets.delete(@pending_global_llm_call_table, :queue)
        else
          :ets.insert(@pending_global_llm_call_table, {:queue, rest})
        end

        call_id

      _ ->
        nil
    end
  end

  defp drop_pending_global_llm_call(call_id) when is_binary(call_id) do
    case :ets.lookup(@pending_global_llm_call_table, :queue) do
      [{:queue, call_ids}] ->
        remaining = List.delete(call_ids, call_id)

        if remaining == [] do
          :ets.delete(@pending_global_llm_call_table, :queue)
        else
          :ets.insert(@pending_global_llm_call_table, {:queue, remaining})
        end

      [] ->
        :ok
    end
  end

  defp drop_pending_global_llm_call(_call_id), do: :ok

  defp enqueue_pending_req_llm_start(agent_context, metadata) when is_map(metadata) do
    pending =
      case :ets.lookup(@pending_req_llm_start_table, :queue) do
        [{:queue, entries}] -> entries
        [] -> []
      end

    entry = %{agent_id: agent_context && agent_context[:agent_id], metadata: metadata}
    :ets.insert(@pending_req_llm_start_table, {:queue, pending ++ [entry]})
  end

  defp adopt_pending_req_llm_start(call_id, turn) when is_binary(call_id) do
    case pop_pending_req_llm_start(turn && turn.agent_id) do
      %{metadata: metadata} when is_map(metadata) ->
        request_id = metadata[:request_id]

        if is_binary(request_id) do
          :ets.insert(@req_llm_lookup_table, {request_id, call_id})
        end

        drop_pending_global_llm_call(call_id)
        apply_req_llm_start_to_call(call_id, metadata)

      _ ->
        :ok
    end
  end

  defp pop_pending_req_llm_start(agent_id) do
    case :ets.lookup(@pending_req_llm_start_table, :queue) do
      [{:queue, entries}] when is_list(entries) and entries != [] ->
        {entry, remaining} = take_pending_req_llm_start(entries, agent_id)

        if remaining == [] do
          :ets.delete(@pending_req_llm_start_table, :queue)
        else
          :ets.insert(@pending_req_llm_start_table, {:queue, remaining})
        end

        entry

      _ ->
        nil
    end
  end

  defp take_pending_req_llm_start(entries, agent_id) when is_binary(agent_id) do
    case Enum.split_while(entries, &(&1.agent_id != agent_id)) do
      {before, [entry | after_entries]} -> {entry, before ++ after_entries}
      {_before, []} -> {hd(entries), tl(entries)}
    end
  end

  defp take_pending_req_llm_start([entry | rest], _agent_id), do: {entry, rest}

  defp request_payload_messages(metadata) do
    request_payload = metadata[:request_payload] || metadata["request_payload"] || %{}
    Map.get(request_payload, :messages) || Map.get(request_payload, "messages") || []
  end

  defp normalize_usage(nil), do: nil
  defp normalize_usage(usage) when is_map(usage), do: Map.new(usage)
  defp normalize_usage(_), do: nil

  defp pick_output_text(turn, record) do
    cond do
      is_binary(turn.text) and turn.text != "" -> turn.text
      is_binary(record.streamed_text) and record.streamed_text != "" -> record.streamed_text
      true -> nil
    end
  end

  defp pick_thinking_text(turn, record) do
    cond do
      is_binary(turn.thinking_content) and turn.thinking_content != "" -> turn.thinking_content
      is_binary(record.streamed_thinking) and record.streamed_thinking != "" -> record.streamed_thinking
      true -> nil
    end
  end

  defp encode_input(nil), do: nil
  defp encode_input(%{arguments: arguments}) when is_binary(arguments), do: arguments
  defp encode_input(%{arguments: arguments}), do: Jason.encode!(arguments)

  defp format_output(nil), do: nil
  defp format_output(%Turn{} = turn), do: turn.text
  defp format_output(%{} = result), do: Turn.extract_text(result)
  defp format_output(result) when is_binary(result), do: result
  defp format_output(result), do: inspect(result)

  defp duration_ms(%{duration_ms: duration_ms}) when is_integer(duration_ms), do: duration_ms

  defp duration_ms(%{duration: duration}) when is_integer(duration) do
    System.convert_time_unit(duration, :native, :millisecond)
  end

  defp duration_ms(_), do: nil

  defp finish_reason_string(nil), do: nil
  defp finish_reason_string(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp finish_reason_string(reason) when is_binary(reason), do: reason
  defp finish_reason_string(reason), do: inspect(reason)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
  defp maybe_put(map, _key, _value, false), do: map
  defp maybe_put(map, _key, nil, _enabled), do: map
  defp maybe_put(map, key, value, true), do: Map.put(map, key, value)

  defp elem_or_nil(nil, _index), do: nil
  defp elem_or_nil(tuple, index), do: elem(tuple, index)
end
