defmodule JidoMurmur.ConversationReadModel.Turn do
  @moduledoc false

  alias JidoMurmur.DisplayMessage
  alias JidoMurmur.DisplayMessage.ToolCall

  @spec step_id(String.t(), pos_integer()) :: String.t()
  def step_id(request_id, step_index) when is_binary(request_id) and is_integer(step_index) and step_index > 0 do
    request_id <> "-step-" <> Integer.to_string(step_index)
  end

  @spec new(String.t(), pos_integer(), keyword()) :: DisplayMessage.t()
  def new(request_id, step_index, opts \\ []) when is_binary(request_id) and is_integer(step_index) and step_index > 0 do
    DisplayMessage.assistant("",
      id: Keyword.get(opts, :id, step_id(request_id, step_index)),
      request_id: request_id,
      step_index: step_index,
      tool_calls: [],
      status: :running,
      first_seen_at: Keyword.get(opts, :first_seen_at),
      first_seen_seq: Keyword.get(opts, :first_seen_seq)
    )
  end

  @spec append_content(DisplayMessage.t(), String.t()) :: DisplayMessage.t()
  def append_content(message, delta) when is_binary(delta) do
    update_message(message, fn current ->
      %{current | content: current.content <> delta, status: :running}
    end)
  end

  @spec append_thinking(DisplayMessage.t(), String.t()) :: DisplayMessage.t()
  def append_thinking(message, delta) when is_binary(delta) do
    update_message(message, fn current ->
      thinking = (current.thinking || "") <> delta
      %{current | thinking: thinking, status: :running}
    end)
  end

  @spec put_response(DisplayMessage.t(), keyword()) :: DisplayMessage.t()
  def put_response(message, opts) when is_list(opts) do
    update_message(message, fn current ->
      tool_calls = Keyword.get(opts, :tool_calls, [])

      updated_tool_calls =
        Enum.reduce(tool_calls, current.tool_calls || [], fn tool_call, acc ->
          upsert_tool_call(normalize_pending_tool_call(tool_call), acc)
        end)

      current
      |> maybe_put_content(Keyword.get(opts, :content))
      |> maybe_put_thinking(Keyword.get(opts, :thinking))
      |> Map.put(:tool_calls, updated_tool_calls)
      |> Map.put(:status, status_from_tool_calls(updated_tool_calls, :completed))
    end)
  end

  @spec merge_pending_tool_calls(DisplayMessage.t(), list()) :: DisplayMessage.t()
  def merge_pending_tool_calls(message, raw_tool_calls) when is_list(raw_tool_calls) do
    pending = Enum.map(raw_tool_calls, &normalize_pending_tool_call/1)

    update_message(message, fn current ->
      %{current | tool_calls: Enum.reduce(pending, current.tool_calls || [], &upsert_tool_call/2), status: :running}
    end)
  end

  @spec put_tool_started(DisplayMessage.t(), map()) :: DisplayMessage.t()
  def put_tool_started(message, data) when is_map(data) do
    tool_call = %ToolCall{
      id: tool_id(data),
      name: tool_name(data),
      args: tool_args(data),
      result: nil,
      status: :running
    }

    update_message(message, fn current ->
      %{current | tool_calls: upsert_tool_call(tool_call, current.tool_calls || []), status: :running}
    end)
  end

  @spec put_tool_result(DisplayMessage.t(), map()) :: DisplayMessage.t()
  def put_tool_result(message, data) when is_map(data) do
    tool_call = %ToolCall{
      id: tool_id(data),
      name: tool_name(data),
      args: tool_args(data),
      result: format_tool_result(data_value(data, :result)),
      status: tool_result_status(data_value(data, :result))
    }

    update_message(message, fn current ->
      updated_tool_calls = upsert_tool_call(tool_call, current.tool_calls || [])
      %{current | tool_calls: updated_tool_calls, status: status_from_tool_calls(updated_tool_calls, current.status || :running)}
    end)
  end

  @spec put_persisted_tool_result(DisplayMessage.t(), String.t() | nil, String.t()) :: DisplayMessage.t()
  def put_persisted_tool_result(message, tool_call_id, result_content) when is_binary(result_content) do
    tool_call = %ToolCall{id: tool_call_id, result: result_content, status: :completed}

    update_message(message, fn current ->
      updated_tool_calls = upsert_tool_call(tool_call, current.tool_calls || [])
      %{current | tool_calls: updated_tool_calls, status: status_from_tool_calls(updated_tool_calls, current.status || :running)}
    end)
  end

  @spec merge_usage(DisplayMessage.t(), map()) :: DisplayMessage.t()
  def merge_usage(message, data) when is_map(data) do
    usage = %{
      input_tokens: data_value(data, :input_tokens) || 0,
      output_tokens: data_value(data, :output_tokens) || 0,
      total_tokens: data_value(data, :total_tokens) || 0,
      model: data_value(data, :model),
      duration_ms: data_value(data, :duration_ms)
    }

    update_message(message, fn current ->
      %{current | usage: merge_usage_maps(current.usage, usage), status: current.status || :running}
    end)
  end

  defp update_message(%DisplayMessage{} = message, updater), do: updater.(message)

  defp maybe_put_content(message, nil), do: message
  defp maybe_put_content(message, ""), do: message

  defp maybe_put_content(message, content) do
    if message.content in [nil, ""] do
      %{message | content: content}
    else
      message
    end
  end

  defp maybe_put_thinking(message, nil), do: message
  defp maybe_put_thinking(message, ""), do: message

  defp maybe_put_thinking(message, thinking) do
    if message.thinking in [nil, ""] do
      %{message | thinking: thinking}
    else
      message
    end
  end

  defp normalize_pending_tool_call(tc) do
    %ToolCall{
      id: data_value(tc, :id),
      name: data_value(tc, :name) || data_value(tc, :function_name) || "tool",
      args: data_value(tc, :arguments) || data_value(tc, :args) || %{},
      result: nil,
      status: :running
    }
  end

  defp upsert_tool_call(%ToolCall{id: nil} = tool_call, tool_calls), do: tool_calls ++ [tool_call]

  defp upsert_tool_call(%ToolCall{id: id} = tool_call, tool_calls) do
    if Enum.any?(tool_calls, &(&1.id == id)) do
      Enum.map(tool_calls, fn
        %ToolCall{id: ^id} = existing -> merge_tool_call(existing, tool_call)
        existing -> existing
      end)
    else
      tool_calls ++ [tool_call]
    end
  end

  defp merge_tool_call(%ToolCall{} = existing, %ToolCall{} = incoming) do
    %ToolCall{
      id: incoming.id || existing.id,
      name: incoming.name || existing.name,
      args: merge_tool_args(existing.args, incoming.args),
      result: incoming.result || existing.result,
      status: incoming.status || existing.status
    }
  end

  defp merge_tool_args(existing, incoming) when incoming in [nil, "", []], do: existing
  defp merge_tool_args(existing, incoming) when is_map(incoming) and map_size(incoming) == 0, do: existing
  defp merge_tool_args(_existing, incoming), do: incoming

  defp status_from_tool_calls([], fallback_status), do: fallback_status

  defp status_from_tool_calls(tool_calls, _fallback_status) do
    if Enum.all?(tool_calls, &(&1.status != :running)) do
      :completed
    else
      :running
    end
  end

  defp tool_id(data) do
    data_value(data, :tool_call_id) || data_value(data, :call_id) || data_value(data, :id)
  end

  defp tool_name(data) do
    data_value(data, :tool_name) || data_value(data, :name) || data_value(data, :tool) || "tool"
  end

  defp tool_args(data) do
    data_value(data, :arguments) || data_value(data, :args) || %{}
  end

  defp data_value(data, key) when is_map(data) do
    Map.get(data, key) || Map.get(data, Atom.to_string(key))
  end

  defp format_tool_result(nil), do: nil
  defp format_tool_result({:ok, result, _effects}), do: truncate_result(inspect(result))
  defp format_tool_result({:error, reason, _effects}), do: truncate_result("Error: #{inspect(reason)}")
  defp format_tool_result({:ok, result}), do: truncate_result(inspect(result))
  defp format_tool_result({:error, reason}), do: truncate_result("Error: #{inspect(reason)}")
  defp format_tool_result(other), do: truncate_result(inspect(other))

  defp truncate_result(str) when is_binary(str) and byte_size(str) > 500, do: String.slice(str, 0, 500) <> "…"
  defp truncate_result(str), do: str

  defp tool_result_status({:ok, _, _}), do: :completed
  defp tool_result_status({:ok, _}), do: :completed
  defp tool_result_status({:error, _, _}), do: :error
  defp tool_result_status({:error, _}), do: :error
  defp tool_result_status(nil), do: :running
  defp tool_result_status(_), do: :completed

  defp merge_usage_maps(nil, usage), do: usage

  defp merge_usage_maps(previous, usage) do
    %{
      input_tokens: (previous.input_tokens || 0) + (usage.input_tokens || 0),
      output_tokens: (previous.output_tokens || 0) + (usage.output_tokens || 0),
      total_tokens: (previous.total_tokens || 0) + (usage.total_tokens || 0),
      model: usage.model || previous.model,
      duration_ms: sum_duration(previous.duration_ms, usage.duration_ms)
    }
  end

  defp sum_duration(nil, nil), do: nil
  defp sum_duration(value, nil), do: value
  defp sum_duration(nil, value), do: value
  defp sum_duration(left, right), do: left + right
end
