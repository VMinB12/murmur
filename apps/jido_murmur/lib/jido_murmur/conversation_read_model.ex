defmodule JidoMurmur.ConversationReadModel do
  @moduledoc """
  Canonical conversation snapshot reduced from persisted thread entries and live
  Murmur/Jido lifecycle facts.
  """

  alias Jido.AI.Signal.LLMResponse
  alias JidoMurmur.ConversationReadModel.Turn
  alias JidoMurmur.DisplayMessage
  alias JidoMurmur.UITurn

  @enforce_keys [:session_id]
  defstruct [:session_id, messages: []]

  @type t :: %__MODULE__{
          session_id: String.t(),
          messages: [DisplayMessage.t()]
        }

  @spec new(String.t(), [DisplayMessage.t()]) :: t()
  def new(session_id, messages \\ []) when is_binary(session_id) and is_list(messages) do
    %__MODULE__{session_id: session_id, messages: messages}
  end

  @spec from_entries(String.t(), list()) :: t()
  def from_entries(session_id, entries) when is_binary(session_id) and is_list(entries) do
    new(session_id, UITurn.project_entries(entries))
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
        upsert_turn(model, request_id, &Turn.append_content(&1, delta))

      {request_id, :thinking, delta} when is_binary(request_id) and is_binary(delta) and delta != "" ->
        upsert_turn(model, request_id, &Turn.append_thinking(&1, delta))

      _ ->
        :ignore
    end
  end

  defp apply_llm_response(model, signal) do
    tool_calls = LLMResponse.extract_tool_calls(signal)

    case {request_id(signal), tool_calls} do
      {request_id, tool_calls} when is_binary(request_id) and tool_calls != [] ->
        upsert_turn(model, request_id, &Turn.merge_pending_tool_calls(&1, tool_calls))

      _ ->
        :ignore
    end
  end

  defp apply_tool_started(model, signal) do
    case request_id(signal) do
      request_id when is_binary(request_id) ->
        upsert_turn(model, request_id, &Turn.put_tool_started(&1, signal.data))

      _ ->
        :ignore
    end
  end

  defp apply_tool_result(model, signal) do
    case request_id(signal) do
      request_id when is_binary(request_id) ->
        upsert_turn(model, request_id, &Turn.put_tool_result(&1, signal.data))

      _ ->
        :ignore
    end
  end

  defp apply_usage(model, signal) do
    case request_id(signal) do
      request_id when is_binary(request_id) ->
        upsert_turn(model, request_id, &Turn.merge_usage(&1, signal.data))

      _ ->
        :ignore
    end
  end

  defp upsert_turn(%__MODULE__{messages: messages} = model, request_id, updater) do
    turn_id = Turn.turn_id(request_id)

    {existing, index} = find_message(messages, turn_id)
    message = existing || Turn.new(request_id)
    updated_message = updater.(message)

    next_messages =
      if is_integer(index) do
        List.replace_at(messages, index, updated_message)
      else
        messages ++ [updated_message]
      end

    {:ok, %{model | messages: next_messages}, updated_message}
  end

  defp find_message(messages, id) do
    case Enum.find_index(messages, &(&1.id == id)) do
      nil -> {nil, nil}
      index -> {Enum.at(messages, index), index}
    end
  end

  defp latest_assistant_message(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find(&DisplayMessage.assistant_message?/1)
  end

  defp request_id(%Jido.Signal{} = signal) do
    data_value(signal.data, :request_id)
  end

  defp data_value(data, key) when is_map(data) do
    Map.get(data, key) || Map.get(data, Atom.to_string(key))
  end
end
