defmodule JidoMurmur.ComposableRequestTransformer do
  @moduledoc """
  A ReAct request transformer that composes multiple transformers in sequence.

  Each transformer in the chain receives the request with any modifications
  from prior transformers applied, and can return additional overrides.
  Overrides are deep-merged in order.

  This is itself a standard `Jido.AI.Reasoning.ReAct.RequestTransformer` —
  when Jido adds native multi-transformer support, consumers can migrate
  away from this module with no other changes.

  ## Configuration

  The transformer list is read from `runtime_context[:request_transformers]`:

      runtime_context = %{
        request_transformers: [MyApp.AuthTransformer, JidoMurmur.MessageInjector],
        # ... other context
      }

  ## Deep-Merge Semantics

  * `:messages` — later transformer replaces earlier (full list replacement)
  * `:llm_opts` — keyword/map merge (last writer wins per key)
  * `:tools`    — later transformer replaces earlier
  * Nested maps — recursively merged
  """

  @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

  @impl true
  def transform_request(request, state, config, runtime_context) do
    transformers = runtime_context[:request_transformers] || []

    Enum.reduce_while(transformers, {:ok, %{}}, fn transformer, {:ok, acc_overrides} ->
      merged_request = apply_overrides(request, acc_overrides)

      case transformer.transform_request(merged_request, state, config, runtime_context) do
        {:ok, new_overrides} ->
          {:cont, {:ok, deep_merge(acc_overrides, new_overrides)}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  defp apply_overrides(request, overrides) when map_size(overrides) == 0, do: request

  defp apply_overrides(request, overrides) do
    Map.merge(request, overrides, fn
      :llm_opts, base, override -> merge_llm_opts(base, override)
      _key, _base, override -> override
    end)
  end

  defp merge_llm_opts(base, override) when is_list(base) and is_list(override) do
    Keyword.merge(base, override)
  end

  defp merge_llm_opts(base, override) when is_map(base) and is_map(override) do
    Map.merge(base, override)
  end

  defp merge_llm_opts(_base, override), do: override

  defp deep_merge(map1, map2) when map_size(map2) == 0, do: map1

  defp deep_merge(map1, map2) do
    Map.merge(map1, map2, fn
      :llm_opts, v1, v2 -> merge_llm_opts(v1, v2)
      _key, v1, v2 when is_map(v1) and is_map(v2) and not is_struct(v1) and not is_struct(v2) ->
        deep_merge(v1, v2)

      _key, _v1, v2 ->
        v2
    end)
  end
end
