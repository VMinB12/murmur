defmodule JidoSql.RequestTransformer do
  @moduledoc """
  ReAct request transformer that composes the standard MessageInjector with
  database schema injection.

  First delegates to `JidoMurmur.MessageInjector` for team context and pending
  messages, then appends the cached database schema to the system message.
  """

  @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

  alias JidoMurmur.Observability

  @impl true
  def transform_request(request, state, config, runtime_context) do
    # First run the standard MessageInjector
    {:ok, base_overrides} =
      JidoMurmur.MessageInjector.transform_request(request, state, config, runtime_context)

    merged_request =
      if map_size(base_overrides) > 0,
        do: Map.merge(request, base_overrides),
        else: request

    # Then inject the schema
    case JidoSql.SchemaIntrospection.cached_schema() do
      nil ->
        {:ok, base_overrides}

      schema_text ->
        messages = inject_schema(merged_request.messages, schema_text)
        record_prepared_input(state, messages)
        {:ok, Map.put(base_overrides, :messages, messages)}
    end
  end

  defp inject_schema(messages, schema_text) do
    suffix = "\n\nDatabase Schema:\n" <> schema_text

    case messages do
      [%{role: :system, content: existing} = sys | rest] ->
        [%{sys | content: existing <> suffix} | rest]

      other ->
        [%{role: :system, content: "You are a SQL assistant." <> suffix} | other]
    end
  end

  defp record_prepared_input(%{llm_call_id: call_id}, messages) when is_binary(call_id) and is_list(messages) do
    Observability.record_prepared_llm_input(call_id, messages)
  end

  defp record_prepared_input(_state, _messages), do: :ok
end
