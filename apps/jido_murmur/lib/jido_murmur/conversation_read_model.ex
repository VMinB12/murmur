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
    defstruct [:session_id, messages: [], step_indexes: %{}, source: :initial, persisted_rev: 0, live_revision: 0]

    @type source :: :initial | :live_thread | :signal | :storage | :visible_message

  @type t :: %__MODULE__{
          session_id: String.t(),
          messages: [DisplayMessage.t()],
      step_indexes: %{optional(String.t()) => pos_integer()},
      source: source(),
      persisted_rev: non_neg_integer(),
      live_revision: non_neg_integer()
        }

  @spec new(String.t(), [DisplayMessage.t()], keyword()) :: t()
  def new(session_id, messages \\ [], opts \\ [])
      when is_binary(session_id) and is_list(messages) and is_list(opts) do
    sorted_messages = DisplayMessage.sort_messages(messages)

    %__MODULE__{
      session_id: session_id,
      messages: sorted_messages,
      step_indexes: Keyword.get(opts, :step_indexes, build_step_indexes(sorted_messages)),
      source: Keyword.get(opts, :source, :initial),
      persisted_rev: normalize_non_neg_integer(Keyword.get(opts, :persisted_rev, 0)),
      live_revision: normalize_non_neg_integer(Keyword.get(opts, :live_revision, 0))
    }
  end

  @spec from_entries(String.t(), list(), keyword()) :: t()
  def from_entries(session_id, entries, opts \\ [])
      when is_binary(session_id) and is_list(entries) and is_list(opts) do
    EntryProjector.project_entries(session_id, entries, opts)
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

  @spec reconcile_entries(t(), list(), keyword()) :: {t(), DisplayMessage.t() | nil}
  def reconcile_entries(%__MODULE__{session_id: session_id}, entries, opts \\ [])
      when is_list(entries) and is_list(opts) do
    next_model = from_entries(session_id, entries, opts)
    {next_model, latest_assistant_message(next_model.messages)}
  end

  @spec ahead_of_persistence?(t()) :: boolean()
  def ahead_of_persistence?(%__MODULE__{live_revision: live_revision}), do: live_revision > 0

  @spec advance_live_revision(t(), source()) :: t()
  def advance_live_revision(%__MODULE__{} = model, source) when is_atom(source) do
    %{model | source: source, live_revision: model.live_revision + 1}
  end

  @spec next_step_index(t(), String.t() | nil) :: pos_integer()
  def next_step_index(%__MODULE__{step_indexes: step_indexes}, request_id) when is_binary(request_id) do
    Map.get(step_indexes, request_id, 0) + 1
  end

  def next_step_index(%__MODULE__{}, _request_id), do: 1

  @spec latest_request_step(t(), String.t() | nil) :: {DisplayMessage.t(), non_neg_integer()} | nil
  def latest_request_step(%__MODULE__{messages: messages}, request_id) when is_binary(request_id) do
    latest_request_step_in_messages(messages, request_id)
  end

  def latest_request_step(%__MODULE__{}, _request_id), do: nil

  @spec put_message(t(), DisplayMessage.t()) :: t()
  def put_message(%__MODULE__{} = model, %DisplayMessage{} = message) do
    update_messages(model, model.messages ++ [message])
  end

  @spec replace_message(t(), non_neg_integer(), DisplayMessage.t()) :: t()
  def replace_message(%__MODULE__{} = model, index, %DisplayMessage{} = message)
      when is_integer(index) and index >= 0 do
    update_messages(model, List.replace_at(model.messages, index, message))
  end

  @spec attach_persisted_tool_result(t(), String.t() | nil, String.t() | nil, String.t()) :: t()
  def attach_persisted_tool_result(%__MODULE__{} = model, request_id, tool_call_id, result_content)
      when is_binary(result_content) do
    case latest_request_step(model, request_id) do
      {message, index} ->
        replace_message(model, index, Turn.put_persisted_tool_result(message, tool_call_id, result_content))

      nil ->
        model
    end
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

  defp upsert_step(%__MODULE__{} = model, request_id, signal, event_type, updater) do
    {message, index} = resolve_step(model, request_id, signal, event_type)

    updated_message = updater.(message)

    next_model =
      if is_integer(index) do
        replace_message(model, index, updated_message)
      else
        put_message(model, updated_message)
      end

    {:ok, advance_live_revision(next_model, :signal), updated_message}
  end

  defp resolve_step(%__MODULE__{} = model, request_id, signal, :llm) do
    case latest_request_step(model, request_id) do
      {message, index} ->
        if continue_current_llm_step?(message) do
          {message, index}
        else
          build_new_step(model, request_id, signal)
        end

      nil ->
        build_new_step(model, request_id, signal)
    end
  end

  defp resolve_step(%__MODULE__{} = model, request_id, signal, :tool) do
    case latest_request_step(model, request_id) do
      {message, index} -> {message, index}
      nil -> build_new_step(model, request_id, signal)
    end
  end

  defp resolve_step(%__MODULE__{} = model, request_id, signal, :usage) do
    case latest_request_step(model, request_id) do
      {message, index} -> {message, index}
      nil -> build_new_step(model, request_id, signal)
    end
  end

  defp build_new_step(%__MODULE__{} = model, request_id, signal) do
    step_index = next_step_index(model, request_id)

    {Turn.new(request_id, step_index,
       first_seen_at: signal_first_seen_at(signal),
       first_seen_seq: signal_first_seen_seq(signal)
     ), nil}
  end

  defp latest_request_step_in_messages(messages, request_id) do
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

  defp update_messages(%__MODULE__{} = model, messages) do
    sorted_messages = DisplayMessage.sort_messages(messages)
    %{model | messages: sorted_messages, step_indexes: build_step_indexes(sorted_messages)}
  end

  defp normalize_non_neg_integer(value) when is_integer(value) and value >= 0, do: value
  defp normalize_non_neg_integer(_value), do: 0

  defp build_step_indexes(messages) do
    Enum.reduce(messages, %{}, &accumulate_step_index/2)
  end

  defp accumulate_step_index(message, step_indexes) do
    case {DisplayMessage.assistant_message?(message), Map.get(message, :request_id), message_step_index(message)} do
      {true, request_id, step_index} when is_binary(request_id) and step_index > 0 ->
        Map.update(step_indexes, request_id, step_index, &max(&1, step_index))

      _ ->
        step_indexes
    end
  end
end
