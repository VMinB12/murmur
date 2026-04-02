# Plan: LLM Observability & Tracing

## Approach

Replace the current AgentObs-based bridge with a Murmur-owned observability subsystem inside `jido_murmur` that models the runtime the way Murmur actually works.

The implementation should establish three explicit layers:

1. **Turn tracing**: one root trace per executed react loop, created and finished by the runner rather than inferred indirectly from lower-level spans.
2. **Child span instrumentation**: LLM and tool spans attach to the active turn trace with Murmur-specific metadata for agent identity, workspace or team correlation, session grouping, interaction grouping, and cross-agent causation.
3. **Payload capture and export**: the subsystem accumulates exact inputs and outputs, including streamed LLM output, then exports OpenInference-compatible span data so Arize Phoenix renders both trace and session views correctly.

The key runtime shift is to treat queued or injected messages as structured envelopes rather than raw strings. That envelope should carry the metadata needed to make trace-boundary decisions: whether the message started a new turn or was injected into an already-running turn, the originating trace or interaction, the sender identity, and any steering classification. This keeps trace semantics rooted in Murmur's actual scheduling behavior instead of retrofitting them after the fact.

To keep future extraction viable without paying the cost now, the new logic should live under a cohesive `JidoMurmur.Observability` namespace with minimal coupling at its boundaries. Existing entry points can be updated or removed, but the subsystem should have a small public surface built around clear responsibilities: turn lifecycle, context propagation, streamed output accumulation, and attribute mapping.

## Key Design Decisions

- **Own the semantics in `jido_murmur`**: Murmur-specific behavior such as react-loop boundaries, queue draining, steering injection, and cross-agent causation belongs in Murmur's codebase until the model stabilizes.
- **Use the runner as the root-trace authority**: `Runner` already defines the real turn boundary, so root traces should start and end there rather than being inferred from individual LLM calls.
- **Promote structured message envelopes**: `PendingQueue`, `Runner`, `MessageInjector`, and `TellAction` should exchange rich metadata, not bare strings, so observability decisions remain deterministic.
- **Keep one session per long-lived agent conversation**: the stable conversation grouping should map to the agent session identity, while workspace and team identity remain additional correlation metadata.
- **Add an explicit interaction identifier**: each user-initiated workflow should have a shared interaction identifier that can flow across agents without collapsing all traces into one session.
- **Accumulate streamed output explicitly**: because current ReqLLM telemetry does not retain the full streamed text, Murmur must accumulate streamed output itself and attach the final content before closing the LLM span.
- **Avoid duplicate instrumentation ownership**: the custom subsystem should become the single source of truth for exported spans so the same turn is not traced twice by overlapping AgentObs and custom handlers.
- **Make payload capture environment-aware**: development should default to full payload visibility, while broader environments should require explicit opt-in.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Parent-child span relationships break across Tasks or process hops | Medium | High | Centralize active turn context in a Murmur-owned context store keyed by turn and request identifiers, and test cross-process propagation explicitly. |
| Streamed output still ends up as placeholders | High | High | Introduce a dedicated request-scoped accumulator for streamed chunks and cover both streamed and non-streamed response paths with tests. |
| Trace boundaries drift from real runner behavior | Medium | High | Start root traces in `Runner` only, and make queue-drain and injection semantics explicit through structured envelopes and integration tests. |
| Cross-agent workflows become hard to follow even with separate traces | Medium | Medium | Propagate `interaction_id`, `triggered_by_agent`, and originating trace metadata through tell and idle-start flows, then verify Phoenix-friendly attributes in tests. |
| Internal observability code becomes hard to extract later | Medium | Medium | Keep new code under a cohesive `JidoMurmur.Observability` namespace and limit direct coupling to runner, queue, and tracer boundaries. |
| Payload capture introduces unwanted sensitivity outside dev | Medium | Medium | Put capture policy behind explicit configuration with safe defaults, and test development vs non-development behavior. |
| Existing tests overfit AgentObs-era assumptions | Medium | Medium | Update focused unit and integration tests around the new observability surface rather than preserving obsolete implementation details. |
