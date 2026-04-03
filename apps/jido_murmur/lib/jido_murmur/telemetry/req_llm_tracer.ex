defmodule JidoMurmur.Telemetry.ReqLLMTracer do
  @moduledoc """
  Bridges ReqLLM telemetry into Murmur's observability store.

  ReqLLM still provides the best source of raw request payloads, especially the
  fully materialized input message list. Murmur now owns span lifecycles itself,
  so this module enriches the active LLM span instead of creating a second span.

  Attach once during application startup:

      JidoMurmur.Telemetry.ReqLLMTracer.attach()
  """

  require Logger

  alias JidoMurmur.Observability
  alias JidoMurmur.Observability.SessionCache

  @handler_id :jido_murmur_req_llm_tracer
  @table __MODULE__

  @doc "Attaches telemetry handlers for ReqLLM request lifecycle events."
  def attach do
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
    agent_context = resolve_agent_context()

    Observability.record_req_llm_start(metadata, agent_context)

    if request_id do
      :ets.insert(@table, {request_id, make_ref(), agent_context})
    end

    :ok
  rescue
    e ->
      Logger.warning("ReqLLMTracer start failed: #{inspect(e)}")
      :ok
  end

  def handle_event([:req_llm, :request, :stop], measurements, metadata, _config) do
    Observability.record_req_llm_stop(measurements, metadata)
    maybe_delete_compat_span(metadata[:request_id])

    :ok
  rescue
    e ->
      Logger.warning("ReqLLMTracer stop failed: #{inspect(e)}")
      :ok
  end

  def handle_event([:req_llm, :request, :exception], _measurements, metadata, _config) do
    Observability.record_req_llm_exception(metadata)
    maybe_delete_compat_span(metadata[:request_id])

    :ok
  rescue
    e ->
      Logger.warning("ReqLLMTracer exception failed: #{inspect(e)}")
      :ok
  end

  # --- message flattening ---

  @doc false
  def flatten_input_messages(messages) when is_list(messages) do
    flatten_messages(messages, :input, "")
  end

  def flatten_input_messages(_), do: %{}

  @doc false
  def flatten_output_messages(messages) when is_list(messages) do
    flatten_messages(messages, :output, "assistant")
  end

  def flatten_output_messages(_), do: %{}

  @doc false
  def flatten_tool_calls(msg_idx, tool_calls, direction) when is_list(tool_calls) do
    prefix = if direction == :input, do: "llm.input_messages", else: "llm.output_messages"

    tool_calls
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {tc, tc_idx}, acc ->
      func = tool_call_field(tc, :function) || %{}
      name = tool_call_field(func, :name) || tool_call_field(tc, :name) || tool_call_field(tc, :function_name)
      args = tool_call_field(func, :arguments) || tool_call_field(tc, :arguments) || tool_call_field(tc, :args)
      id = tool_call_field(tc, :id)

      encoded_args = encode_jsonish(args)

      tool_call_key = "#{prefix}.#{msg_idx}.message.tool_calls.#{tc_idx}.tool_call"
      function_key = "#{tool_call_key}.function"

      acc
      |> maybe_put("#{tool_call_key}.id", id)
      |> maybe_put("#{function_key}.name", name)
      |> maybe_put("#{function_key}.arguments", encoded_args)
    end)
  end

  def flatten_tool_calls(_msg_idx, _tool_calls, _direction), do: %{}

  defp tool_call_field(value, key) when is_map(value) do
    Map.get(value, key) || Map.get(value, Atom.to_string(key))
  end

  defp tool_call_field(_value, _key), do: nil

  defp flatten_messages(messages, direction, default_role) do
    messages
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {msg, idx}, acc ->
      Map.merge(acc, flatten_message(msg, idx, direction, default_role))
    end)
  end

  defp flatten_message(msg, idx, direction, default_role) do
    prefix = message_prefix(direction, idx)
    tool_calls = msg[:tool_calls] || msg["tool_calls"]

    prefix
    |> flatten_message_base(msg, default_role)
    |> maybe_merge_tool_calls(idx, tool_calls, direction)
  end

  defp flatten_message_base(prefix, msg, default_role) do
    %{}
    |> Map.put("#{prefix}.message.role", message_role(msg, default_role))
    |> maybe_put("#{prefix}.message.content", message_content(msg))
    |> maybe_put("#{prefix}.message.name", message_name(msg))
    |> maybe_put("#{prefix}.message.tool_call_id", message_tool_call_id(msg))
    |> maybe_put("#{prefix}.message.function_call_name", message_function_call_name(msg))
    |> maybe_put(
      "#{prefix}.message.function_call_arguments_json",
      encode_jsonish(message_function_call_arguments(msg))
    )
  end

  defp maybe_merge_tool_calls(base, _idx, tool_calls, _direction) when tool_calls in [nil, []], do: base

  defp maybe_merge_tool_calls(base, idx, tool_calls, direction) do
    Map.merge(base, flatten_tool_calls(idx, tool_calls, direction))
  end

  defp message_prefix(:input, idx), do: "llm.input_messages.#{idx}"
  defp message_prefix(:output, idx), do: "llm.output_messages.#{idx}"

  defp message_role(msg, default_role), do: to_string(map_value(msg, :role, default_role))
  defp message_content(msg), do: extract_content(map_value(msg, :content))
  defp message_name(msg), do: map_value(msg, :name)
  defp message_tool_call_id(msg), do: map_value(msg, :tool_call_id)
  defp message_function_call_name(msg), do: map_value(msg, :function_call_name)

  defp message_function_call_arguments(msg) do
    map_value(msg, :function_call_arguments_json) || map_value(msg, :function_call_arguments)
  end

  defp map_value(msg, key, default \\ nil) do
    Map.get(msg, key, Map.get(msg, Atom.to_string(key), default))
  end

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

  defp maybe_delete_compat_span(nil), do: :ok
  defp maybe_delete_compat_span(request_id), do: :ets.delete(@table, request_id)

  defp resolve_agent_context do
    agent_id =
      case Logger.metadata()[:agent_id] do
        nil ->
          case Process.get(:jido_agent_id) do
            nil -> resolve_agent_id_from_ancestors()
            id -> id
          end

        id ->
          id
      end

    case agent_id do
      nil ->
        nil

      id ->
        base_id = id |> String.split("/") |> hd()

        case SessionCache.lookup(base_id) do
          {workspace_id, display_name} ->
            %{agent_id: base_id, workspace_id: workspace_id, display_name: display_name}

          nil ->
            nil
        end
    end
  rescue
    _ -> nil
  end

  defp resolve_agent_id_from_ancestors do
    registry = jido_registry()
    if registry, do: find_agent_in_ancestry(registry)
  rescue
    _ -> nil
  end

  defp find_agent_in_ancestry(registry) do
    (Process.get(:"$callers", []) ++ Process.get(:"$ancestors", []))
    |> Enum.find_value(fn
      pid when is_pid(pid) -> agent_id_for_pid(registry, pid)
      _ -> nil
    end)
  end

  defp agent_id_for_pid(registry, pid) do
    case Registry.keys(registry, pid) do
      [agent_id | _] -> agent_id
      _ -> nil
    end
  end

  defp jido_registry do
    jido_mod = Application.get_env(:jido_murmur, :jido_mod)
    if jido_mod, do: Module.concat(jido_mod, Registry)
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

  def extract_response_messages(%{context: %{messages: messages}}) when is_list(messages) do
    messages
    |> Enum.filter(fn msg ->
      role = to_string(msg[:role] || msg["role"] || "")
      role == "assistant"
    end)
  end

  def extract_response_messages(%{"context" => %{"messages" => messages}}) when is_list(messages) do
    extract_response_messages(%{context: %{messages: messages}})
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

  def system(metadata), do: provider(metadata)

  defp output_text(%{response_summary: %{text: text}}) when is_binary(text) and text != "", do: text

  defp output_text(%{response_summary: %{text_bytes: bytes}}) when is_integer(bytes) and bytes > 0,
    do: "[streamed response: #{bytes} bytes]"

  defp output_text(_), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  defp encode_jsonish(value) when is_map(value), do: Jason.encode!(value)
  defp encode_jsonish(value) when is_binary(value), do: value
  defp encode_jsonish(_), do: nil
end
