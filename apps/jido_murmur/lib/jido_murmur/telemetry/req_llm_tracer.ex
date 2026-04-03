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

    Observability.record_req_llm_start(metadata)

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
            %{workspace_id: workspace_id, display_name: display_name}

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

  defp output_text(%{response_summary: %{text: text}}) when is_binary(text) and text != "", do: text

  defp output_text(%{response_summary: %{text_bytes: bytes}}) when is_integer(bytes) and bytes > 0,
    do: "[streamed response: #{bytes} bytes]"

  defp output_text(_), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)
end
