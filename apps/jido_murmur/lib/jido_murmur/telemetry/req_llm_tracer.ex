defmodule JidoMurmur.Telemetry.ReqLLMTracer do
  @moduledoc """
  Bridges ReqLLM telemetry events to OpenTelemetry spans with OpenInference
  semantic conventions for Arize Phoenix.

  ReqLLM emits `[:req_llm, :request, :start | :stop | :exception]` telemetry
  events on every LLM call. This handler converts them into OTel spans so they
  appear in Arize Phoenix without modifying any upstream dependency code.

  For streaming calls, the `:start` event fires in the caller process while
  `:stop` fires in the StreamServer GenServer. Span context is stored in an
  ETS table keyed by `request_id` so it works across processes.

  ## Streaming limitation

  ReqLLM's streaming telemetry does not include the accumulated response text.
  The StreamServer sends text chunks directly to the stream consumer without
  storing them in telemetry metadata. For streaming calls, `output.value` shows
  a byte-count indicator instead of the actual response content.

  Attach once during application startup:

      JidoMurmur.Telemetry.ReqLLMTracer.attach()
  """

  require OpenTelemetry.Tracer, as: Tracer
  require Logger

  alias JidoMurmur.ObsTracer.Cache, as: ObsCache

  @handler_id :jido_murmur_req_llm_tracer
  @table __MODULE__

  @doc "Attaches telemetry handlers for ReqLLM request lifecycle events."
  def attach do
    # Create ETS table for cross-process span context sharing (streaming)
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    end

    events = [
      [:req_llm, :request, :start],
      [:req_llm, :request, :stop],
      [:req_llm, :request, :exception]
    ]

    :telemetry.attach_many(@handler_id, events, &__MODULE__.handle_event/4, %{})
    Logger.debug("JidoMurmur.Telemetry.ReqLLMTracer: Attached to [:req_llm, :request, :*]")
  end

  @doc "Detaches the telemetry handler. Useful in tests."
  def detach do
    :telemetry.detach(@handler_id)
  end

  @doc false
  def handle_event([:req_llm, :request, :start], _measurements, metadata, _config) do
    request_id = metadata[:request_id]

    model_name = model_name(metadata)
    provider = provider(metadata)

    # Base span attributes
    attributes =
      %{
        "openinference.span.kind" => "LLM",
        "llm.model_name" => model_name,
        "gen_ai.system" => provider,
        "gen_ai.request.model" => model_name
      }
      |> maybe_put("session.id", metadata[:session_id])

    # Flatten input messages from request_payload (US1)
    input_msg_attrs =
      case get_in(metadata, [:request_payload, :messages]) do
        messages when is_list(messages) and messages != [] ->
          flatten_input_messages(messages)
          |> maybe_put("input.value", extract_input_value(messages))

        _ ->
          %{}
      end

    # Agent/session enrichment from ObsTracer.Cache (US4, US5)
    agent_context = resolve_agent_context()

    agent_attrs =
      case agent_context do
        %{workspace_id: wid, display_name: name} ->
          %{}
          |> maybe_put("session.id", wid)
          |> maybe_put("llm.agent_name", name)

        _ ->
          %{}
      end

    all_attrs = Map.merge(attributes, input_msg_attrs) |> Map.merge(agent_attrs)

    span_ctx = Tracer.start_span("LLM #{model_name}", %{attributes: all_attrs})

    if request_id do
      :ets.insert(@table, {request_id, span_ctx, agent_context})
    end

    :ok
  rescue
    e ->
      Logger.warning("ReqLLMTracer start failed: #{inspect(e)}")
      :ok
  end

  def handle_event([:req_llm, :request, :stop], measurements, metadata, _config) do
    case take_span(metadata[:request_id]) do
      nil ->
        :ok

      {span_ctx, _agent_context} ->
        usage = metadata[:usage] || %{}
        input_tokens = Map.get(usage, :input_tokens, 0) || 0
        output_tokens = Map.get(usage, :output_tokens, 0) || 0

        stop_attrs =
          %{
            "llm.token_count.prompt" => input_tokens,
            "llm.token_count.completion" => output_tokens,
            "llm.token_count.total" => input_tokens + output_tokens,
            "gen_ai.usage.input_tokens" => input_tokens,
            "gen_ai.usage.output_tokens" => output_tokens
          }
          |> maybe_put("gen_ai.response.finish_reasons", finish_reason_string(metadata[:finish_reason]))

        output_msg_attrs = build_output_attrs(metadata)

        duration_ms = Map.get(measurements, :duration, 0) |> System.convert_time_unit(:native, :millisecond)

        all_stop_attrs =
          Map.merge(stop_attrs, output_msg_attrs)
          |> Map.put("llm.latency_ms", duration_ms)

        OpenTelemetry.Span.set_attributes(span_ctx, Map.to_list(all_stop_attrs))
        OpenTelemetry.Span.end_span(span_ctx)
    end

    :ok
  rescue
    e ->
      Logger.warning("ReqLLMTracer stop failed: #{inspect(e)}")
      :ok
  end

  def handle_event([:req_llm, :request, :exception], _measurements, metadata, _config) do
    case take_span(metadata[:request_id]) do
      nil ->
        :ok

      {span_ctx, _agent_context} ->
        error = metadata[:error]

        OpenTelemetry.Span.set_attributes(span_ctx, [
          {"error", true},
          {"error.message", inspect(error)}
        ])

        OpenTelemetry.Span.set_status(span_ctx, OpenTelemetry.status(:error, inspect(error)))
        OpenTelemetry.Span.end_span(span_ctx)
    end

    :ok
  rescue
    e ->
      Logger.warning("ReqLLMTracer exception failed: #{inspect(e)}")
      :ok
  end

  # --- span context storage ---

  defp take_span(nil), do: nil

  defp take_span(request_id) do
    case :ets.take(@table, request_id) do
      [{^request_id, span_ctx, agent_context}] -> {span_ctx, agent_context}
      [{^request_id, span_ctx}] -> {span_ctx, nil}
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  # --- message flattening ---

  @doc false
  def flatten_input_messages(messages) when is_list(messages) do
    messages
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {msg, idx}, acc ->
      role = to_string(msg[:role] || msg["role"] || "")
      content = extract_content(msg[:content] || msg["content"])

      base =
        acc
        |> Map.put("llm.input_messages.#{idx}.message.role", role)
        |> maybe_put("llm.input_messages.#{idx}.message.content", content)

      # tool calls on input messages (e.g. assistant messages with tool_calls in history)
      tool_calls = msg[:tool_calls] || msg["tool_calls"]

      if is_list(tool_calls) and tool_calls != [] do
        Map.merge(base, flatten_tool_calls(idx, tool_calls, :input))
      else
        base
      end
    end)
  end

  def flatten_input_messages(_), do: %{}

  @doc false
  def flatten_output_messages(messages) when is_list(messages) do
    messages
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {msg, idx}, acc ->
      role = to_string(msg[:role] || msg["role"] || "assistant")
      content = extract_content(msg[:content] || msg["content"])

      base =
        acc
        |> Map.put("llm.output_messages.#{idx}.message.role", role)
        |> maybe_put("llm.output_messages.#{idx}.message.content", content)

      tool_calls = msg[:tool_calls] || msg["tool_calls"]

      if is_list(tool_calls) and tool_calls != [] do
        Map.merge(base, flatten_tool_calls(idx, tool_calls, :output))
      else
        base
      end
    end)
  end

  def flatten_output_messages(_), do: %{}

  @doc false
  def flatten_tool_calls(msg_idx, tool_calls, direction) when is_list(tool_calls) do
    prefix = if direction == :input, do: "llm.input_messages", else: "llm.output_messages"

    tool_calls
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {tc, tc_idx}, acc ->
      func = tc[:function] || tc["function"] || %{}
      name = func[:name] || func["name"]
      args = func[:arguments] || func["arguments"]

      encoded_args =
        case args do
          a when is_map(a) -> Jason.encode!(a)
          a when is_binary(a) -> a
          _ -> nil
        end

      base_key = "#{prefix}.#{msg_idx}.message.tool_calls.#{tc_idx}.tool_call.function"

      acc
      |> maybe_put("#{base_key}.name", name)
      |> maybe_put("#{base_key}.arguments", encoded_args)
    end)
  end

  def flatten_tool_calls(_msg_idx, _tool_calls, _direction), do: %{}

  @doc false
  def extract_content(content) when is_binary(content) and content != "", do: content

  def extract_content(parts) when is_list(parts) do
    parts
    |> Enum.filter(fn
      %{type: :text} -> true
      %{"type" => "text"} -> true
      _ -> false
    end)
    |> Enum.map_join("", fn
      %{text: text} -> text
      %{"text" => text} -> text
      _ -> ""
    end)
    |> case do
      "" -> nil
      text -> text
    end
  end

  def extract_content(_), do: nil

  @doc false
  def extract_input_value(messages) when is_list(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn msg ->
      role = to_string(msg[:role] || msg["role"] || "")

      if role == "user" do
        extract_content(msg[:content] || msg["content"])
      end
    end)
  end

  def extract_input_value(_), do: nil

  @doc false
  def extract_output_value(messages) when is_list(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn msg ->
      role = to_string(msg[:role] || msg["role"] || "")

      if role == "assistant" do
        extract_content(msg[:content] || msg["content"])
      end
    end)
  end

  def extract_output_value(_), do: nil

  # --- agent context resolution ---

  defp resolve_agent_context do
    agent_id =
      case Logger.metadata()[:agent_id] do
        nil -> Process.get(:jido_agent_id)
        id -> id
      end

    case agent_id do
      nil ->
        nil

      id ->
        case ObsCache.lookup(id) do
          {workspace_id, display_name} ->
            %{workspace_id: workspace_id, display_name: display_name}

          nil ->
            nil
        end
    end
  rescue
    _ -> nil
  end

  # --- response message extraction ---

  @doc false
  def build_output_attrs(metadata) do
    case metadata[:response_payload] do
      payload when is_map(payload) ->
        messages = extract_response_messages(payload)

        if messages == [] do
          # Streaming: response_payload has only status/usage (no message content).
          # ReqLLM streaming telemetry does not accumulate response text.
          # Fall back to response_summary.text (non-streaming) or text_bytes indicator.
          maybe_put(%{}, "output.value", output_text(metadata))
        else
          flatten_output_messages(messages)
          |> maybe_put("output.value", extract_output_value(messages))
        end

      _ ->
        maybe_put(%{}, "output.value", output_text(metadata))
    end
  end

  @doc false
  def extract_response_messages(%{choices: choices}) when is_list(choices) do
    Enum.map(choices, fn
      %{message: msg} when is_map(msg) -> msg
      _ -> %{role: "assistant", content: ""}
    end)
  end

  def extract_response_messages(%{text: text}) when is_binary(text) do
    [%{role: "assistant", content: text}]
  end

  def extract_response_messages(%{content: content}) when is_binary(content) do
    [%{role: "assistant", content: content}]
  end

  def extract_response_messages(%{message: msg}) when is_map(msg) do
    [msg]
  end

  def extract_response_messages(_), do: []

  # --- helpers ---

  @doc false
  def model_name(%{model: %{id: id}}), do: to_string(id)
  def model_name(%{model: model}) when is_binary(model), do: model
  def model_name(_), do: "unknown"

  @doc false
  def provider(%{model: %{provider: p}}), do: to_string(p)
  def provider(%{provider: p}) when is_binary(p), do: p
  def provider(_), do: "unknown"

  defp finish_reason_string(nil), do: nil
  defp finish_reason_string(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp finish_reason_string(reason) when is_binary(reason), do: reason
  defp finish_reason_string(reason), do: inspect(reason)

  defp output_text(%{response_summary: %{text: text}}) when is_binary(text) and text != "", do: text

  defp output_text(%{response_summary: %{text_bytes: bytes}}) when is_integer(bytes) and bytes > 0,
    do: "[streamed response: #{bytes} bytes]"

  defp output_text(_), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)
end
