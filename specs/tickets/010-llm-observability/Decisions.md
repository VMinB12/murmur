# Decisions: LLM Observability & Tracing

## Open

No open questions at this time.

## Resolved

### Q1: Should this ticket continue to depend on AgentObs?

**Decision**: No. The ticket should move to a Murmur-owned custom implementation and treat AgentObs as superseded.

**Date**: 2026-04-02

**Rationale**: The runtime semantics Murmur cares about are not generic OpenTelemetry wiring problems. They are domain decisions about how react loops, injected steering messages, agent conversations, and cross-agent causation should appear to developers. Owning that layer directly produces a cleaner codebase and allows intentional breaking changes while the model is being established.

### Q2: Should the custom observability implementation stay inside `jido_murmur` for now, or be extracted immediately into a separate package?

**Decision**: Keep the implementation inside `jido_murmur` for now, but structure it so future extraction remains straightforward.

**Date**: 2026-04-02

**Rationale**: The tracing semantics are still Murmur-specific and still evolving. Keeping the work local avoids locking a premature public API while still leaving room to split the subsystem out later once the model is proven.

### Q3: What should the primary session identifier represent in Phoenix?

**Decision**: The primary session identifier should represent the long-lived conversation history of a single agent, while workspace or team identity remains correlation metadata.

**Date**: 2026-04-02

**Rationale**: This preserves the distinction between per-turn traces and per-agent history, keeps the Phoenix session view useful, and avoids flattening a whole team into one oversized session.

### Q4: Do we want an explicit cross-agent interaction identifier in addition to trace and session identifiers?

**Decision**: Yes. Add a dedicated interaction identifier shared across work caused by one initiating prompt or workflow.

**Date**: 2026-04-02

**Rationale**: Trace identifiers are too narrow and session identifiers are too long-lived. A separate interaction identifier gives team-level workflow reconstruction without distorting the trace or session model.

### Q5: What should the default capture policy be for prompt, response, and tool payload content outside local development?

**Decision**: Capture full content in development by default and require explicit opt-in for broader environments.

**Date**: 2026-04-02

**Rationale**: This keeps local debugging high-fidelity while making non-development environments opt in deliberately when the extra visibility is worth the sensitivity trade-off.

### Q6: Where should full conversation structure live in the exported traces?

**Decision**: Root agent-turn spans may remain summary-oriented, but LLM child spans are the canonical place for full ordered input conversations and structured assistant output messages.

**Date**: 2026-04-03

**Rationale**: The Phoenix UI renders message-oriented views from LLM span attributes, not from a generic turn-summary text field. Keeping the root span compact avoids duplicating long conversations while making the detailed LLM spans the place where developers inspect system, user, assistant, tool, and tool-call structure.

### Q7: Should assistant output be exported as a message even when the runtime mainly accumulates plain streamed text?

**Decision**: Yes. The implementation must materialize a structured assistant output message for every completed LLM span, including tool-call metadata when present.

**Date**: 2026-04-03

**Rationale**: Text-only `output.value` is not enough for the Phoenix trace view. Developers need to inspect the assistant reply in the same structural format as the model conversation, and tool-calling responses need their tool calls preserved as output-message data rather than flattened away.