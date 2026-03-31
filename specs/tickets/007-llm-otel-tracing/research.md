# Research: LLM OpenTelemetry Tracing

**Feature Branch**: `007-llm-otel-tracing`  
**Date**: 2026-03-30

## R1: How to capture input/output messages in telemetry events

### Problem Statement

The current `ReqLLMTracer` creates OpenTelemetry spans for every LLM call, but spans are "empty" — they lack input messages, output messages, and tool calls. The root cause is that ReqLLM's telemetry events only include **summaries** (counts, byte sizes) by default, not actual message content.

### Findings

ReqLLM telemetry metadata by default:
- `request_summary` — contains `message_count`, `text_bytes`, `image_part_count`, `tool_call_count` (counts only)
- `response_summary` — contains `text_bytes`, `thinking_bytes`, `tool_call_count`, `image_count`, `object?` (counts only)
- Neither summary includes actual message text, roles, or tool call objects

ReqLLM supports a `payloads: :raw` configuration that populates two additional metadata fields:
- `request_payload` — the full sanitized request context including the messages array and tools array
- `response_payload` — the full response data including text, tool calls, and finish reason

### Decision: Enable `payloads: :raw` via application config

**Rationale**: This is the simplest approach — a single config line enables full payload data in telemetry events. No dependency modifications, no monkey-patching, no changes to the ReAct runner.

**Configuration**:
```elixir
config :req_llm, telemetry: [payloads: :raw]
```

**Alternatives considered**:

| Alternative | Rejected Because |
|-------------|-----------------|
| Wrap `ReqLLM.Generation.stream_text` calls with `AgentObs.ReqLLM` traced variants | Requires modifying `jido_ai` dependency code (ReAct runner) — breaks on dependency updates |
| Listen to Jido.Observe events at agent level instead of ReqLLM level | Jido observe events carry orchestration metadata, not raw LLM request/response payloads |
| Custom telemetry middleware between ReAct runner and ReqLLM | Over-engineered; ReqLLM already provides the toggle |

**Trade-off**: Raw payloads increase telemetry event memory by including full message content. For LLM calls with large context windows (100k+ tokens), this means the full prompt text exists twice in memory briefly (once in the request, once in telemetry metadata). This is acceptable for a dev/observability tool and can be toggled off in production via environment config.

---

## R2: OpenInference attribute mapping for Arize Phoenix

### Problem Statement

Arize Phoenix expects spans to carry OpenInference semantic convention attributes. Without the correct attribute names and structure, Phoenix cannot render message bubbles, tool call panels, or token dashboards.

### Findings

The `AgentObs.Handlers.Phoenix.Translator` module already implements the full OpenInference mapping. The key attribute patterns are:

**Input messages** (flattened per-message, 0-indexed):
```
llm.input_messages.{N}.message.role        → "user" | "assistant" | "system" | "tool"
llm.input_messages.{N}.message.content     → message text
llm.input_messages.{N}.message.tool_calls.{M}.tool_call.function.name       → tool name
llm.input_messages.{N}.message.tool_calls.{M}.tool_call.function.arguments  → JSON string
```

**Output messages** (same pattern):
```
llm.output_messages.{N}.message.role
llm.output_messages.{N}.message.content
llm.output_messages.{N}.message.tool_calls.{M}.tool_call.function.name
llm.output_messages.{N}.message.tool_calls.{M}.tool_call.function.arguments
```

**Derived values**:
```
input.value   → last user message content (for Phoenix search/summary)
output.value  → last assistant message content
```

**Token counts**:
```
llm.token_count.prompt       → input token count
llm.token_count.completion   → output token count
llm.token_count.total        → sum
```

### Decision: Implement flattening logic in ReqLLMTracer, referencing the Translator patterns

**Rationale**: The Translator module is inside `agent_obs` (a dependency). Calling it directly couples our handler to its internal API. Instead, implement the same flattening pattern in our handler — it's ~40 lines of code and gives us full control over attribute construction.

**Alternative considered**: Calling `AgentObs.Handlers.Phoenix.Translator.from_start_metadata/2` directly. Rejected because the Translator expects metadata in a specific format (`:input_messages`, `:output_messages` keys) that doesn't match ReqLLM's `request_payload`/`response_payload` structure. Adapting the metadata to fit the Translator's expected format would be as much code as implementing the flattening directly.

---

## R3: Cross-process span context for streaming calls

### Problem Statement

Streaming LLM calls emit `[:req_llm, :request, :start]` in the caller process and `[:req_llm, :request, :stop]` in the `StreamServer` GenServer — a different BEAM process.

### Findings

The current `ReqLLMTracer` already solves this with an ETS table keyed by `request_id`. Both start and stop events include `request_id` in metadata, so the span context is stored on start and retrieved (via `take`) on stop regardless of which process handles each event.

### Decision: Keep ETS-based approach (already implemented)

**Rationale**: Working correctly. 17 tests pass including a dedicated cross-process streaming test. No changes needed.

---

## R4: Session and agent identity enrichment

### Problem Statement

LLM traces need `session.id` (workspace) and agent display name. The `ReqLLMTracer` currently receives ReqLLM telemetry events which don't carry workspace or agent information.

### Findings

- `JidoMurmur.ObsTracer.Cache` stores `{agent_id, workspace_id, display_name}` tuples in an ETS table
- `Cache.lookup(agent_id)` returns `{workspace_id, display_name}` or `nil`
- The agent_id is NOT present in ReqLLM telemetry metadata (ReqLLM knows nothing about Jido agents)
- The ReAct runner runs inside an `AgentServer` process. The process's registered name or state contains the agent_id

### Decision: Use process metadata via `Logger.metadata` or `Process.get` to propagate agent context

**Rationale**: The Jido framework already sets process metadata during agent execution. The agent_id (and by extension workspace_id via Cache lookup) can be read from the current process's metadata in the `:start` handler. For streaming (cross-process stop), store agent context alongside the span context in ETS.

**Alternative considered**: Passing agent_id through ReqLLM opts. Rejected because it requires modifying the ReAct runner in `jido_ai` dependency. Using process-level metadata is non-invasive and works with the existing call chain.

**Fallback**: If process metadata is not reliably set, agent identity attributes will be omitted (degraded but not broken). Session/agent enrichment is P3 priority.

---

## R5: Fault tolerance and performance

### Problem Statement

Tracing must not crash the application or add meaningful latency.

### Findings

- All handler functions already wrap in `rescue` blocks, logging warnings on failure
- ETS operations are O(1) read/write with `read_concurrency: true`
- OpenTelemetry batch processor handles export asynchronously — span creation is non-blocking
- OpenInference attribute flattening is pure map manipulation — microsecond-level cost

### Decision: No additional fault tolerance needed

The existing rescue wrappers in every `handle_event` clause, combined with OTel's async batch export and ETS's concurrent read design, satisfy the <50ms overhead requirement and the "no crash" requirement.
