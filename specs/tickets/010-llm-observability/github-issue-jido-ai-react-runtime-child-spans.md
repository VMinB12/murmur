# GitHub Issue Draft: ReAct runtime does not expose observable child span lifecycle for LLM and tool execution

## Title

ReAct runtime bypasses external tracer lifecycle for LLM/tool execution, making nested OpenTelemetry spans impossible without patching

## Summary

When using the Task-based ReAct runtime, the top-level request lifecycle is visible, but the actual LLM and tool execution steps do not expose enough externally observable lifecycle to build real nested `LLM` and `TOOL` spans from an embedding application.

The runtime internally knows about:

- `llm_call_id`
- `tool_call_id`
- `tool_name`
- LLM start/completion
- tool start/completion
- iteration boundaries

However, those lifecycle transitions are either handled entirely inside the runtime or reduced to partial signals that are insufficient for an external tracer to create accurate child spans.

This blocks integrations such as OpenInference / Arize Phoenix where an application wants:

- one root agent/request span
- nested `LLM` child spans for each model call
- nested `TOOL` child spans for each tool execution
- correct parent/child relationships
- accurate durations
- call-level input/output attribution

## Current Behavior

### LLM execution

The ReAct runner performs ReqLLM calls directly in the runtime:

- streaming path via `ReqLLM.Generation.stream_text/3`
- non-streaming path via `ReqLLM.Generation.generate_text/3`

Relevant code:

- `deps/jido_ai/lib/jido_ai/reasoning/react/runner.ex`

The runtime emits internal ReAct events such as:

- `:llm_started`
- `:llm_delta`
- `:llm_completed`

but these are not exposed as a public tracer lifecycle around the actual request execution.

### Tool execution

The ReAct runner executes tools directly with its own retry logic and emits internal events such as:

- `:tool_started`
- `:tool_completed`

but external consumers only reliably see the final tool-result signal, not a start event with stable timing and correlation metadata.

### What an embedding app can observe today

From outside `jido_ai`, an embedding app can see some combination of:

- root request lifecycle
- `ai.llm.delta`
- `ai.llm.response`
- `ai.tool.result`
- ReqLLM request telemetry

That is not enough to reconstruct exact child spans because:

1. ReqLLM request telemetry does not provide the ReAct `llm_call_id` needed to distinguish multiple LLM calls within one request.
2. `:llm_started` is not surfaced as an externally consumable signal with the same `llm_call_id` used later by `ai.llm.response`.
3. `:tool_started` is not surfaced as an externally consumable signal with timing metadata suitable for span start.
4. Tool execution duration is computed inside the runner but not exposed through a start/stop tracer hook that an embedding app can attach to.

## Expected Behavior

An embedding application should be able to implement a custom tracer without patching `jido_ai` and still produce real nested spans.

At minimum, the runtime should expose one of these supported integration points:

### Option A: Wrap runtime execution in `Jido.AI.Observe.start_span/3`

For each ReAct LLM/tool execution, call the existing observability span helpers around the real work and include stable metadata:

- `request_id`
- `run_id`
- `iteration`
- `llm_call_id`
- `tool_call_id`
- `tool_name`
- `model`

This would allow configured `Jido.Observe.Tracer` implementations to create real child spans automatically.

### Option B: Emit public runtime lifecycle signals or telemetry with stable IDs

Expose signals or telemetry for:

- `llm_started`
- `llm_completed`
- `tool_started`
- `tool_completed`

and include stable correlation fields on both start and completion:

- `request_id`
- `run_id`
- `iteration`
- `llm_call_id` or `tool_call_id`
- `tool_name`
- `model`
- start/stop timing or duration

This would let external apps build spans themselves.

## Why This Matters

This currently prevents a clean OpenTelemetry / OpenInference integration for the ReAct runtime.

In our case, the app can create a root `AGENT` span for a request, but it cannot reliably create nested `LLM` and `TOOL` spans for the actual live runtime without either:

- patching `jido_ai` locally, or
- falling back to heuristics that break when a request contains multiple model/tool iterations.

That means trace viewers such as Arize Phoenix show only the root request/agent span, even though the runtime internally knows the per-call structure.

## Concrete Reproduction

1. Configure a custom `Jido.Observe.Tracer` implementation.
2. Run a ReAct agent that performs at least one LLM call and one tool call.
3. Export spans to an OTLP-compatible backend such as Arize Phoenix.
4. Observe that the root request/agent span is present.
5. Observe that nested `LLM` / `TOOL` spans are missing or cannot be correlated accurately from public hooks alone.

## Relevant Code References

- `deps/jido_ai/lib/jido_ai/reasoning/react/runner.ex`
- `deps/jido_ai/lib/jido_ai/reasoning/react/strategy.ex`
- `deps/jido_ai/lib/jido_ai/reasoning/react/event.ex`
- `deps/jido_ai/lib/jido_ai/observe.ex`
- `deps/jido/lib/jido/observe.ex`

## Requested Resolution

Please expose a supported child-span lifecycle for ReAct LLM and tool execution so downstream apps can create correct nested spans without patching dependency code.

The cleanest outcome would be for the ReAct runtime to use `Jido.AI.Observe.start_span/3`, `finish_span/2`, and `finish_span_error/4` around its own LLM and tool execution paths, since those hooks already integrate with the configured `Jido.Observe.Tracer` behavior.

## Additional Notes

The runtime already tracks the right IDs and lifecycle events internally, so this appears to be an observability-surface gap rather than a missing-data problem.