# Plan: Native ReAct Steering Adoption

## Approach

Refactor Murmur's message delivery path around a single ingress coordinator actor per agent session.

The coordinator becomes the only Murmur-owned process allowed to decide whether a new input should:

- start a fresh `ask/await` run
- be routed into the active run with `steer/3`
- be routed into the active run with `inject/3`

All external producers, including UI events, inter-agent `tell`, and internal automation, send canonical ingress input to the coordinator instead of directly deciding which runtime API to call.

The redesigned runtime model is:

1. Normalize inbound input into a jido_ai-aligned ingress contract using `content`, `source`, `refs`, and optional `expected_request_id`.
2. Deliver that input to the session's ingress coordinator actor.
3. The coordinator inspects current runtime state and chooses `ask` when idle, `steer` for human-visible busy-run follow-up, or `inject` for inter-agent or programmatic busy-run follow-up.
4. If the target run changes while delivery is in flight, the coordinator retries against the latest state rather than relying on a Murmur-owned semantic queue.
5. Request transformers remain only for Murmur-owned context shaping such as team instructions and SQL schema enrichment.

This approach deliberately removes the old custom delivery abstraction. The only remaining coordination should be the normal mailbox behavior of the ingress coordinator actor and the native per-run pending-input behavior inside `jido_ai`.

## Key Design Decisions

### 1. Introduce a per-session ingress coordinator actor

Use a dedicated OTP process per agent session to own delivery decisions.

Rationale:

- keeps ask-versus-steer routing inside one actor boundary
- matches the actor-model explanation the team wants to standardize on
- avoids stale state decisions being made independently across multiple caller processes
- provides one stable place for retry, telemetry, and contract normalization

This is an architectural change and should be captured in an ADR when implementation begins.

### 2. Align Murmur's ingress data contract to jido_ai

The canonical ingress input should mirror jido_ai's control payload shape as closely as possible:

- `content` — user-style text to deliver
- `source` — origin descriptor for the input
- `refs` — Murmur metadata such as `interaction_id`, `sender_name`, `sender_trace_id`, workspace context, and causation
- `expected_request_id` — optional run correlation for busy-run delivery

Avoid retaining a Murmur-specific session-envelope contract with separate top-level fields such as `role`, `kind`, and custom queue-only identifiers unless a field is strictly needed for Murmur-owned routing.

Rationale:

- reduces translation overhead
- makes upstream semantics easier to adopt directly
- keeps Murmur-specific metadata inside the extension point that jido_ai already exposes

### 3. Use direct `ask` when idle and native steering when busy

The normal rule should be explicit:

- idle target: start a fresh run immediately with `ask`
- busy target and human-origin follow-up: `steer`
- busy target and inter-agent or programmatic follow-up: `inject`

Rationale:

- removes the need for a semantic pre-run mailbox
- keeps active-run control where it belongs, inside jido_ai
- makes runtime behavior easier to reason about and document

### 4. Remove message delivery from `MessageInjector`

`MessageInjector` should be split or reduced so it only performs Murmur-specific request shaping, such as team instructions. SQL-specific schema injection remains in its own transformer path.

Rationale:

- separates delivery concerns from prompt-shaping concerns
- avoids preserving a workaround after upstream support exists
- keeps request transformers composable and easier to test

### 5. Treat race handling as coordinator logic, not queue semantics

If a busy-run delivery attempt is rejected because the active request changed or completed, the coordinator should re-evaluate current state and retry. This should not be modeled as a Murmur mailbox that accumulates work items as a first-class domain concept.

Rationale:

- preserves the clean architecture the team wants
- keeps buffering transient and implementation-local
- avoids reviving the same complexity under a different name

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Run-boundary retries become subtle and error-prone | Medium | High | Centralize all retries inside the coordinator actor and cover busy-to-idle, request-mismatch, and completed-run transitions with focused tests |
| Data contract migration breaks observability or conversation grouping | Medium | High | Define the canonical `refs` schema up front and update tracing and grouping code in the same refactor rather than as a follow-up |
| Retaining old queue assumptions in callers leads to a mixed architecture | High | High | Make the coordinator the only supported public delivery API and remove direct caller-side routing decisions during implementation |
| Request transformer responsibilities remain muddy after the refactor | Medium | Medium | Split team-context shaping from delivery logic explicitly and update package-specific transformers to build on the new boundary |
| Per-session coordinator lifecycle adds supervision complexity | Low | Medium | Reuse established OTP patterns with explicit naming, supervision, and cleanup tied to agent session lifecycle |
| Documentation drift leaves the old queue model discoverable after migration | Medium | Medium | Update Architecture docs, package docs, generator templates, and tests as part of the same implementation ticket |