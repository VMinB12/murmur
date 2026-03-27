# `encode_reasoning_effort` should support map values for OpenAI reasoning `summary` parameter

## Problem

`encode_reasoning_effort/1` in the Responses API provider only accepts atoms and binaries, producing a
map with a single `"effort"` key:

```elixir
defp encode_reasoning_effort(effort) when is_atom(effort),
  do: %{"effort" => Atom.to_string(effort)}
```

This means the request body always sends:

```json
{"reasoning": {"effort": "medium"}}
```

However, OpenAI's Responses API also accepts a `summary` parameter inside the `reasoning` object.
Without `"summary": "auto"`, the API **does not return reasoning content** in streaming
`response.reasoning.delta` events or in the final response — even though the model reasons internally.

From the [OpenAI Responses API docs](https://platform.openai.com/docs/api-reference/responses/create):

```json
{"reasoning": {"effort": "medium", "summary": "auto"}}
```

Since `encode_reasoning_effort` only accepts atoms/binaries and hard-codes the `%{"effort" => ...}`
shape, there is **no way** for callers to pass the `summary` parameter through the existing
`reasoning_effort` option.

## Proposed Solution

Accept maps in addition to atoms/binaries, passing them through with stringified keys:

```elixir
defp encode_reasoning_effort(nil), do: nil

defp encode_reasoning_effort(effort) when is_map(effort) do
  effort
  |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
  |> Map.new()
end

defp encode_reasoning_effort(effort) when is_atom(effort),
  do: %{"effort" => Atom.to_string(effort)}

defp encode_reasoning_effort(effort) when is_binary(effort), do: %{"effort" => effort}
defp encode_reasoning_effort(_), do: nil
```

This is fully backwards-compatible. Existing atom/binary callers are unaffected. Map callers get full
control over the reasoning request body.

## Usage

```elixir
# Existing usage (unchanged)
ReqLLM.Generation.stream_text(model, messages, reasoning_effort: :medium)

# New: also request reasoning summaries
ReqLLM.Generation.stream_text(model, messages,
  reasoning_effort: %{effort: :medium, summary: :auto}
)
```

## Context

- Affects: `ReqLLM.Providers.OpenAI.ResponsesAPI`
- File: `lib/req_llm/providers/openai/responses_api.ex`
- Function: `encode_reasoning_effort/1` (private)
- Also called from: `build_request_body/4` (used by both `encode_body/1` and `attach_stream/4`)
- Models affected: `o3`, `o3-mini`, `o4-mini`, `gpt-5-mini` and other reasoning models
- ReqLLM version: 1.8.0

## Alternatives Considered

- **Separate `reasoning_summary` option**: Would require plumbing a new option through all layers.
  The map approach is simpler and more forward-compatible with future OpenAI reasoning parameters.
- **`provider_options` passthrough**: `provider_options` doesn't support arbitrary body field
  injection, so this isn't possible without additional changes.
