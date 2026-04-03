# Plan: LLM Observability & Tracing

## Approach

Replace the current AgentObs-based bridge with a Murmur-owned observability subsystem inside `jido_murmur` that models the runtime the way Murmur actually works.

The attribute-level export mapping for this plan lives in [data-contract.md](data-contract.md) and is the normative source for span field names and message-shape requirements.

The implementation should establish three explicit layers:

1. **Turn tracing**: one root trace per executed react loop, created and finished by the runner rather than inferred indirectly from lower-level spans.
2. **Child span instrumentation**: LLM and tool spans attach to the active turn trace with Murmur-specific metadata for agent identity, workspace or team correlation, session grouping, interaction grouping, and cross-agent causation.
3. **Payload capture and message rendering**: the subsystem accumulates exact inputs and outputs, including streamed LLM output, and exports OpenInference-compatible message attributes so Arize Phoenix renders full input conversations and assistant output messages instead of only text summaries.

The rendering contract needs to be explicit:

- **Root turn spans stay summary-oriented**. They may expose compact `input.value` and `output.value` fields for quick scanning, but they are not the canonical place for full message history.
- **LLM child spans are the canonical detailed view**. They must carry ordered `llm.input_messages.*` and `llm.output_messages.*` attributes so Phoenix can show system, user, assistant, tool, and assistant-tool-call structure natively.
- **Assistant output must be materialized as a message**. Even when the runtime primarily thinks in terms of accumulated streamed text, the exported LLM span should finish with a structured assistant message payload, not only a plain `output.value` string.

The key runtime shift is to treat queued or injected messages as structured envelopes rather than raw strings. That envelope should carry the metadata needed to make trace-boundary decisions: whether the message started a new turn or was injected into an already-running turn, the originating trace or interaction, the sender identity, and any steering classification. This keeps trace semantics rooted in Murmur's actual scheduling behavior instead of retrofitting them after the fact.

To keep future extraction viable without paying the cost now, the new logic should live under a cohesive `JidoMurmur.Observability` namespace with minimal coupling at its boundaries. Existing entry points can be updated or removed, but the subsystem should have a small public surface built around clear responsibilities: turn lifecycle, context propagation, streamed output accumulation, and attribute mapping.

## Key Design Decisions

- **Own the semantics in `jido_murmur`**: Murmur-specific behavior such as react-loop boundaries, queue draining, steering injection, and cross-agent causation belongs in Murmur's codebase until the model stabilizes.
- **Use the runner as the root-trace authority**: `Runner` already defines the real turn boundary, so root traces should start and end there rather than being inferred from individual LLM calls.
- **Promote structured message envelopes**: `PendingQueue`, `Runner`, `MessageInjector`, and `TellAction` should exchange rich metadata, not bare strings, so observability decisions remain deterministic.
- **Keep one session per long-lived agent conversation**: the stable conversation grouping should map to the agent session identity, while workspace and team identity remain additional correlation metadata.
- **Add an explicit interaction identifier**: each user-initiated workflow should have a shared interaction identifier that can flow across agents without collapsing all traces into one session.
- **Accumulate streamed output explicitly**: because current ReqLLM telemetry does not retain the full streamed text, Murmur must accumulate streamed output itself and attach the final content before closing the LLM span.
- **Treat Phoenix message rendering as part of the contract**: it is not enough to store semantically correct text fields. The exported attributes must align with Phoenix's message-oriented OpenInference rendering so developers can inspect the full conversation structure directly in the UI.
- **Avoid duplicate instrumentation ownership**: the custom subsystem should become the single source of truth for exported spans so the same turn is not traced twice by overlapping AgentObs and custom handlers.
- **Make payload capture environment-aware**: development should default to full payload visibility, while broader environments should require explicit opt-in.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Parent-child span relationships break across Tasks or process hops | Medium | High | Centralize active turn context in a Murmur-owned context store keyed by turn and request identifiers, and test cross-process propagation explicitly. |
| Streamed output still ends up as placeholders | High | High | Introduce a dedicated request-scoped accumulator for streamed chunks and cover both streamed and non-streamed response paths with tests. |
| Phoenix still renders only plain text despite payload capture improvements | High | High | Treat `llm.input_messages.*` and `llm.output_messages.*` as a first-class export contract, add focused tests for assistant-output and tool-call attributes, and verify the Phoenix UI against real traces. |
| Trace boundaries drift from real runner behavior | Medium | High | Start root traces in `Runner` only, and make queue-drain and injection semantics explicit through structured envelopes and integration tests. |
| Cross-agent workflows become hard to follow even with separate traces | Medium | Medium | Propagate `interaction_id`, `triggered_by_agent`, and originating trace metadata through tell and idle-start flows, then verify Phoenix-friendly attributes in tests. |
| Internal observability code becomes hard to extract later | Medium | Medium | Keep new code under a cohesive `JidoMurmur.Observability` namespace and limit direct coupling to runner, queue, and tracer boundaries. |
| Payload capture introduces unwanted sensitivity outside dev | Medium | Medium | Put capture policy behind explicit configuration with safe defaults, and test development vs non-development behavior. |
| Existing tests overfit AgentObs-era assumptions | Medium | Medium | Update focused unit and integration tests around the new observability surface rather than preserving obsolete implementation details. |
