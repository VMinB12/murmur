# Data Model: LLM OpenTelemetry Tracing

**Feature Branch**: `007-llm-otel-tracing`  
**Date**: 2026-03-30

## Overview

This feature does not introduce database tables or Ecto schemas. All data flows through in-memory structures: BEAM process telemetry events → ETS span context storage → OpenTelemetry span attributes → OTLP export. The "data model" here describes the in-memory entity shapes and their relationships.

## Entities

### LLM Call Span

Represents a single LLM invocation as an OpenTelemetry span with OpenInference attributes.

| Attribute | Source | Type | Required |
|-----------|--------|------|----------|
| `openinference.span.kind` | Constant | `"LLM"` | Yes |
| `llm.model_name` | `metadata.model` | string | Yes |
| `gen_ai.system` | `metadata.model.provider` | string | Yes |
| `gen_ai.request.model` | `metadata.model` | string | Yes |
| `llm.input_messages.{N}.message.role` | `request_payload.messages[N].role` | string | Yes (per message) |
| `llm.input_messages.{N}.message.content` | `request_payload.messages[N].content` | string | Yes (per message) |
| `llm.input_messages.{N}.message.tool_calls.{M}.tool_call.function.name` | Nested in message | string | If present |
| `llm.input_messages.{N}.message.tool_calls.{M}.tool_call.function.arguments` | Nested in message | JSON string | If present |
| `llm.output_messages.{N}.message.role` | `response_payload` | string | Yes (per message) |
| `llm.output_messages.{N}.message.content` | `response_payload` | string | Yes (per message) |
| `llm.output_messages.{N}.message.tool_calls.{M}.tool_call.function.name` | `response_payload` | string | If present |
| `llm.output_messages.{N}.message.tool_calls.{M}.tool_call.function.arguments` | `response_payload` | JSON string | If present |
| `input.value` | Last user message content | string | Yes |
| `output.value` | Last assistant message content | string | Yes |
| `llm.token_count.prompt` | `metadata.usage.input_tokens` | integer | Yes |
| `llm.token_count.completion` | `metadata.usage.output_tokens` | integer | Yes |
| `llm.token_count.total` | Sum | integer | Yes |
| `gen_ai.usage.input_tokens` | `metadata.usage.input_tokens` | integer | Yes |
| `gen_ai.usage.output_tokens` | `metadata.usage.output_tokens` | integer | Yes |
| `gen_ai.response.finish_reasons` | `metadata.finish_reason` | string | Yes |
| `llm.latency_ms` | `measurements.duration` | integer | Yes |
| `session.id` | `ObsTracer.Cache` lookup | string | If available |
| `llm.agent_name` | `ObsTracer.Cache` lookup | string | If available |

### ETS Span Context Entry

Stored in the `JidoMurmur.Telemetry.ReqLLMTracer` ETS table for cross-process span tracking.

| Field | Type | Description |
|-------|------|-------------|
| Key: `request_id` | string | Unique request ID from ReqLLM telemetry |
| Value: `span_ctx` | OTel span context | OpenTelemetry span reference |
| Value: `agent_context` | map or nil | `%{agent_id, workspace_id, display_name}` captured at start |

### Message Structure (from `request_payload`)

The messages within `request_payload` follow the ReqLLM normalized format:

```
%{
  role: "user" | "assistant" | "system" | "tool",
  content: string | [%{type: :text, text: string}],
  tool_calls: [%{function: %{name: string, arguments: map}}] | nil,
  tool_call_id: string | nil,
  name: string | nil
}
```

## Relationships

```
Session (workspace_id)
  └── Agent (agent_id, display_name)
       └── LLM Call Span (request_id)
            ├── Input Messages [0..N]
            │    └── Tool Calls [0..M] (if role=assistant)
            └── Output Messages [0..N]
                 └── Tool Calls [0..M] (if finish_reason=tool_calls)
```

## State Transitions

An LLM Call Span has the following lifecycle:

```
Created (start event)
  │
  ├── Completed (stop event) → attributes set, span ended
  │
  └── Failed (exception event) → error status set, span ended
```

For streaming: start and stop may occur in different BEAM processes. The ETS table bridges this gap via `request_id`.

## Validation Rules

- `request_id` must be non-nil for ETS storage (spans without request_id are fire-and-forget)
- Token counts default to 0 if not provided by the model provider
- Message content may be empty string but role must always be present
- Tool call arguments are JSON-encoded strings (not raw maps)
- Session and agent attributes are best-effort — omitted if cache lookup fails
