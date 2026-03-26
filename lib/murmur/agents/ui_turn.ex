defmodule Murmur.Agents.UITurn do
  @moduledoc """
  Transforms raw Jido thread entries into structured display groups.

  A UITurn represents one agent "turn" — everything from the LLM receiving a
  prompt until it produces a final answer, including any thinking traces and
  tool call/result pairs along the way.
  """

  defmodule ToolCall do
    @moduledoc false
    defstruct [:id, :name, :args, :result, :status]

    @type t :: %__MODULE__{
            id: String.t(),
            name: String.t(),
            args: map(),
            result: String.t() | nil,
            status: :running | :completed | :error
          }
  end

  defstruct [:id, :thinking, :tool_calls, :content, :sender_name, :status]

  @type t :: %__MODULE__{
          id: String.t(),
          thinking: String.t() | nil,
          tool_calls: [ToolCall.t()],
          content: String.t(),
          sender_name: String.t() | nil,
          status: :thinking | :tool_calling | :completed | :error
        }

  @doc """
  Converts Jido thread entries into display messages that preserve
  thinking and tool call structure.

  Returns a flat list of maps with role/content plus optional
  `:thinking`, `:tool_calls` fields for assistant messages.
  """
  @spec project_entries([struct()]) :: [map()]
  def project_entries(entries) when is_list(entries) do
    entries
    |> Enum.filter(&relevant_entry?/1)
    |> group_by_request()
    |> Enum.flat_map(&request_group_to_messages/1)
  end

  # --- Private: Entry filtering ---

  defp relevant_entry?(%{kind: kind}) when kind in [:message, :ai_message], do: true
  defp relevant_entry?(_), do: false

  # --- Private: Grouping ---

  defp group_by_request(entries) do
    entries
    |> Enum.chunk_while([], &chunk_entry/2, &flush_chunk/1)
    |> Enum.reject(&(&1 == []))
  end

  defp chunk_entry(%{kind: :message} = entry, []), do: {:cont, [entry], []}
  defp chunk_entry(%{kind: :message} = entry, acc), do: {:cont, acc, [entry]}

  defp chunk_entry(entry, []) do
    {:cont, [entry]}
  end

  defp chunk_entry(entry, [%{kind: :message} | _] = acc) do
    {:cont, acc, [entry]}
  end

  defp chunk_entry(entry, acc) do
    if same_request?(hd(acc), entry),
      do: {:cont, acc ++ [entry]},
      else: {:cont, acc, [entry]}
  end

  defp flush_chunk([]), do: {:cont, []}
  defp flush_chunk(acc), do: {:cont, acc, []}

  defp same_request?(a, b) do
    req_a = get_request_id(a)
    req_a != nil and req_a == get_request_id(b)
  end

  defp get_request_id(%{payload: payload}) do
    payload[:request_id] || payload["request_id"]
  end

  # --- Private: Group → Messages ---

  defp request_group_to_messages([%{kind: :message} = entry]) do
    [
      %{
        id: entry.id || Ecto.UUID.generate(),
        role: "user",
        content: get_payload(entry, :content, ""),
        sender_name: get_payload(entry, :sender_name)
      }
    ]
  end

  defp request_group_to_messages(entries) do
    {thinking, tool_calls, content, sender_name} =
      Enum.reduce(entries, {nil, [], "", nil}, &reduce_entry/2)

    id = (hd(entries).id || Ecto.UUID.generate()) <> "-turn"

    [
      %{
        id: id,
        role: "assistant",
        content: content,
        sender_name: sender_name,
        thinking: if(thinking && thinking != "", do: thinking),
        tool_calls: tool_calls
      }
    ]
  end

  defp reduce_entry(entry, acc) do
    payload = entry.payload || %{}
    role = to_string(payload[:role] || payload["role"])

    case role do
      "assistant" -> reduce_assistant(payload, acc)
      "tool" -> reduce_tool(payload, acc)
      _ -> acc
    end
  end

  defp reduce_assistant(payload, {think, tools, _text, _name}) do
    new_think = payload[:thinking] || payload["thinking"] || think
    new_text = payload[:content] || payload["content"] || ""
    new_name = payload[:sender_name] || payload["sender_name"]
    raw_tcs = payload[:tool_calls] || payload["tool_calls"] || []

    new_tools = tools ++ Enum.map(raw_tcs, &parse_tool_call/1)

    {new_think, new_tools, new_text, new_name}
  end

  defp reduce_tool(payload, {think, tools, text, name}) do
    call_id = payload[:tool_call_id] || payload["tool_call_id"]
    result_content = payload[:content] || payload["content"] || ""

    updated_tools =
      Enum.map(tools, fn tc ->
        if tc.id == call_id, do: %{tc | result: result_content, status: :completed}, else: tc
      end)

    {think, updated_tools, text, name}
  end

  defp parse_tool_call(tc) do
    %ToolCall{
      id: tc_field(tc, :id),
      name: tc_field(tc, :name) || tc_field(tc, :function_name),
      args: tc_field(tc, :arguments) || tc_field(tc, :args) || %{},
      result: nil,
      status: :running
    }
  end

  # --- Private: Field access ---

  defp get_payload(%{payload: payload}, key, default \\ nil) do
    payload[key] || payload[to_string(key)] || default
  end

  defp tc_field(tc, key) when is_struct(tc), do: Map.get(tc, key)
  defp tc_field(tc, key) when is_map(tc), do: Map.get(tc, key) || Map.get(tc, to_string(key))
end
