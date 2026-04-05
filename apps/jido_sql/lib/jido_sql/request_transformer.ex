defmodule JidoSql.RequestTransformer do
  @moduledoc """
  ReAct request transformer that composes the standard MessageInjector with
  database schema injection.

  First delegates to `JidoMurmur.MessageInjector` for team context, then
  appends the cached database schema to the system message.
  """

  @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

  alias JidoMurmur.Observability

  @impl true
  def transform_request(request, state, config, runtime_context) do
    # First run the standard team-context transformer.
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
        Observability.record_prepared_llm_input(state, messages)
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
end
