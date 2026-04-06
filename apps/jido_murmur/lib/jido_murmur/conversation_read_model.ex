defmodule JidoMurmur.ConversationReadModel do
  @moduledoc """
  Canonical conversation snapshot reduced from persisted thread entries and live
  Murmur/Jido lifecycle facts.
  """

  alias Jido.AI.Signal.LLMResponse
  alias Jido.Signal.ID, as: SignalID
  alias JidoMurmur.ConversationReadModel.EntryProjector
  alias JidoMurmur.ConversationReadModel.Turn
  alias JidoMurmur.DisplayMessage

  @enforce_keys [:session_id]
  defstruct [:session_id, messages: []]

  @type t :: %__MODULE__{
          session_id: String.t(),
          messages: [DisplayMessage.t()]
        }

  @spec new(String.t(), [DisplayMessage.t()]) :: t()
  def new(session_id, messages \\ []) when is_binary(session_id) and is_list(messages) do
    %__MODULE__{session_id: session_id, messages: DisplayMessage.sort_messages(messages)}
  end

  @spec from_entries(String.t(), list()) :: t()
  def from_entries(session_id, entries) when is_binary(session_id) and is_list(entries) do
    new(session_id, EntryProjector.project_entries(entries))
  end

  @spec apply_signal(t(), Jido.Signal.t()) :: {:ok, t(), DisplayMessage.t()} | :ignore
  def apply_signal(%__MODULE__{} = model, %Jido.Signal{type: type} = signal) do
    case type do
      "ai.llm.delta" -> apply_llm_delta(model, signal)
      "ai.llm.response" -> apply_llm_response(model, signal)
      "ai.tool.started" -> apply_tool_started(model, signal)
      "ai.tool.result" -> apply_tool_result(model, signal)
      "ai.usage" -> apply_usage(model, signal)
      _ -> :ignore
    end
  end

  @spec reconcile_entries(t(), list()) :: {t(), DisplayMessage.t() | nil}
  def reconcile_entries(%__MODULE__{session_id: session_id}, entries) when is_list(entries) do
    next_model = from_entries(session_id, entries)
    {next_model, latest_assistant_message(next_model.messages)}
  end

  defp apply_llm_delta(model, signal) do
    case {request_id(signal), data_value(signal.data, :chunk_type), data_value(signal.data, :delta)} do
      {request_id, :content, delta} when is_binary(request_id) and is_binary(delta) and delta != "" ->
        upsert_step(model, request_id, signal, :llm, &Turn.append_content(&1, delta))

      {request_id, :thinking, delta} when is_binary(request_id) and is_binary(delta) and delta != "" ->
        upsert_step(model, request_id, signal, :llm, &Turn.append_thinking(&1, delta))

      _ ->
        :ignore
    end
  end

  defp apply_llm_response(model, signal) do
    case request_id(signal) do
      request_id when is_binary(request_id) ->
        upsert_step(model, request_id, signal, :llm, fn message ->
          Turn.put_response(message,
            content: llm_response_text(signal),
            thinking: llm_response_thinking(signal),
            tool_calls: LLMResponse.extract_tool_calls(signal)
          )
        end)

      _ ->
        :ignore
    end
  end

  defp apply_tool_started(model, signal) do
    case request_id(signal) do
      request_id when is_binary(request_id) ->
        upsert_step(model, request_id, signal, :tool, &Turn.put_tool_started(&1, signal.data))

      _ ->
        :ignore
    end
  end

  defp apply_tool_result(model, signal) do
    case request_id(signal) do
      request_id when is_binary(request_id) ->
        upsert_step(model, request_id, signal, :tool, &Turn.put_tool_result(&1, signal.data))

      _ ->
        :ignore
    end
  end

  defp apply_usage(model, signal) do
    case request_id(signal) do
      request_id when is_binary(request_id) ->
        upsert_step(model, request_id, signal, :usage, &Turn.merge_usage(&1, signal.data))

      _ ->
        :ignore
    end
  end

  defp upsert_step(%__MODULE__{messages: messages} = model, request_id, signal, event_type, updater) do
    {message, index} = resolve_step(messages, request_id, signal, event_type)

    updated_message = updater.(message)

    next_messages =
      if is_integer(index) do
        List.replace_at(messages, index, updated_message)
      else
        messages ++ [updated_message]
      end

    sorted_messages = DisplayMessage.sort_messages(next_messages)
    {:ok, %{model | messages: sorted_messages}, updated_message}
  end

  defp resolve_step(messages, request_id, signal, :llm) do
    case latest_request_step(messages, request_id) do
      {message, index} ->
        if continue_current_llm_step?(message) do
          {message, index}
        else
          build_new_step(messages, request_id, signal)
        end

      nil ->
        build_new_step(messages, request_id, signal)
    end
  end

  defp resolve_step(messages, request_id, signal, :tool) do
    case latest_request_step(messages, request_id) do
      {message, index} -> {message, index}
      nil -> build_new_step(messages, request_id, signal)
    end
  end

  defp resolve_step(messages, request_id, signal, :usage) do
    case latest_request_step(messages, request_id) do
      {message, index} -> {message, index}
      nil -> build_new_step(messages, request_id, signal)
    end
  end

  defp build_new_step(messages, request_id, signal) do
    step_index = next_step_index(messages, request_id)

    {Turn.new(request_id, step_index,
       first_seen_at: signal_first_seen_at(signal),
       first_seen_seq: signal_first_seen_seq(signal)
     ), nil}
  end

  defp latest_request_step(messages, request_id) do
    messages
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find_value(fn {message, index} ->
      if DisplayMessage.assistant_message?(message) and Map.get(message, :request_id) == request_id do
        {message, index}
      end
    end)
  end

  defp continue_current_llm_step?(message) do
    Map.get(message, :status) == :running and (Map.get(message, :tool_calls) || []) == []
  end

  defp next_step_index(messages, request_id) do
    messages
    |> Enum.filter(&(DisplayMessage.assistant_message?(&1) and Map.get(&1, :request_id) == request_id))
    |> Enum.map(&message_step_index/1)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  defp message_step_index(message) do
    case Map.get(message, :step_index) do
      step_index when is_integer(step_index) and step_index > 0 -> step_index
      _ -> 0
    end
  end

  defp latest_assistant_message(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find(&DisplayMessage.assistant_message?/1)
  end

  defp request_id(%Jido.Signal{} = signal) do
    data_value(signal.data, :request_id) || metadata_value(signal, :request_id)
  end

  defp metadata_value(%Jido.Signal{data: data}, key) when is_map(data) do
    case data_value(data, :metadata) do
      metadata when is_map(metadata) -> data_value(metadata, key)
      _ -> nil
    end
  end

  defp metadata_value(_signal, _key), do: nil

  defp llm_response_text(%Jido.Signal{data: data}) do
    case data_value(data, :result) do
      {:ok, result} when is_map(result) -> data_value(result, :text)
      {:ok, result, _effects} when is_map(result) -> data_value(result, :text)
      _ -> nil
    end
  end

  defp llm_response_thinking(%Jido.Signal{data: data}) do
    data_value(data, :thinking_content) ||
      case data_value(data, :result) do
        {:ok, result} when is_map(result) -> data_value(result, :thinking_content)
        {:ok, result, _effects} when is_map(result) -> data_value(result, :thinking_content)
        _ -> nil
      end
  end

  defp data_value(data, key) when is_map(data) do
    Map.get(data, key) || Map.get(data, Atom.to_string(key))
  end

  defp signal_first_seen_at(%Jido.Signal{id: id}) when is_binary(id) do
    if SignalID.valid?(id), do: SignalID.extract_timestamp(id), else: generated_signal_timestamp()
  end

  defp signal_first_seen_at(_signal) do
    generated_signal_timestamp()
  end

  defp signal_first_seen_seq(%Jido.Signal{id: id}) when is_binary(id) do
    if SignalID.valid?(id), do: SignalID.sequence_number(id), else: generated_signal_sequence()
  end

  defp signal_first_seen_seq(_signal) do
    generated_signal_sequence()
  end

  defp generated_signal_timestamp do
    fallback_id = SignalID.generate!()
    SignalID.extract_timestamp(fallback_id)
  end

  defp generated_signal_sequence do
    fallback_id = SignalID.generate!()
    SignalID.sequence_number(fallback_id)
  end
end
