# Spec: Native ReAct Steering Adoption

## User Stories

### US-1: Native active-run follow-up delivery (Priority: P1)

**As a** Murmur maintainer, **I want** follow-up input sent to a currently running ReAct loop to use native `jido_ai` steering controls, **so that** Murmur stops owning a custom mid-run message injection mechanism.

**Independent test**: Start a long-running agent turn, send a direct human follow-up and an inter-agent follow-up while the run is active, and verify they reach the active run through native steering rather than through a custom queue drain in `MessageInjector`.

### US-2: Preserve idle wake-up and no-drop delivery semantics (Priority: P1)

**As a** workspace user, **I want** idle agents to start a fresh run immediately and busy agents to accept follow-up input through native steering, **so that** Murmur does not need a separate semantic ingress queue for normal delivery.

**Independent test**: Send input to an idle agent and verify a new run starts from that single message plus persisted history. Send input to a busy agent and verify the follow-up is routed through native steering. Send input at an active-run boundary and verify Murmur resolves the race without requiring a persistent mailbox contract.

### US-3: Keep Murmur-specific request shaping independent from follow-up delivery (Priority: P1)

**As a** package maintainer, **I want** team instructions and package-specific context injection to remain supported independently of follow-up routing, **so that** Murmur can adopt native steering without losing dynamic prompt enrichment.

**Independent test**: Verify a general agent still receives workspace team instructions and a SQL agent still receives schema context, while busy-agent follow-up delivery no longer depends on `MessageInjector` draining queued messages.

### US-4: Preserve metadata and observability across the new control path (Priority: P1)

**As a** developer debugging multi-agent behavior, **I want** follow-up messages delivered through native steering to preserve interaction and origin metadata, **so that** traces, causation, and workspace conversation grouping remain trustworthy after the refactor.

**Independent test**: Inject a follow-up input with Murmur interaction metadata and verify the receiving run retains stable correlation data for conversation grouping and trace linking.

### US-5: Single coordination boundary for delivery decisions (Priority: P1)

**As a** Murmur maintainer, **I want** one per-session coordinator actor to own the ask-versus-steer delivery decision, **so that** actor-model guarantees apply to the delivery protocol instead of leaving those choices to multiple external callers.

**Independent test**: Send near-simultaneous inputs from multiple producers to the same session and verify that one coordinator actor serializes the routing decisions without exposing a semantic Murmur mailbox.

### US-6: Reduce Murmur-owned runtime surface area (Priority: P2)

**As a** Murmur maintainer, **I want** the codebase to remove or narrow custom queueing and transformer logic that only exists to emulate missing upstream behavior, **so that** future upgrades follow native `jido_ai` capabilities instead of preserving historical workarounds.

**Independent test**: Inspect the runtime path and verify that Murmur no longer uses its previous Murmur-owned follow-up mechanism as the primary mechanism for active-run input, and that any Murmur-owned buffering is purely an internal race-serialization detail rather than a semantic inbox or mailbox contract.

## Acceptance Criteria

- [x] Busy human follow-up input is routed through native `steer/3`.
- [x] Busy inter-agent or programmatic follow-up input is routed through native `inject/3`.
- [x] A single Murmur-owned coordinator actor per agent session is the only supported boundary for deciding whether inbound input becomes `ask`, `steer`, or `inject`.
- [x] External callers do not independently inspect session state to choose between `ask`, `steer`, and `inject`.
- [x] Murmur only attempts native steering when a ReAct run is active, and uses current-run correlation when available to avoid attaching input to the wrong run.
- [x] If the target agent is idle, Murmur starts a fresh `ask/await` run directly from the incoming message and persisted history rather than enqueueing the message into a Murmur-owned semantic mailbox.
- [x] If a native steering call rejects because the active run has just ended or changed, Murmur resolves that race by retrying against the current runtime state, including starting a fresh run when appropriate, instead of relying on a long-lived Murmur ingress queue.
- [x] Murmur no longer depends on `MessageInjector` to drain busy-agent follow-up messages into request messages.
- [x] Dynamic team instructions remain injected for agents that require workspace context.
- [x] SQL schema injection remains available for the SQL agent or any equivalent package-specific request-shaping path.
- [x] Murmur defines and documents a jido_ai-aligned ingress contract using `content`, `source`, `refs`, and optional `expected_request_id`, including how `interaction_id`, `sender_name`, `sender_trace_id`, and workspace causation are preserved.
- [x] Cross-agent `tell` keeps its fire-and-forget semantics while still waking idle targets and steering busy targets in place.
- [x] Active-run follow-up input remains visible to Murmur's observability and conversation-grouping systems with stable causation and interaction metadata.
- [x] Murmur does not expose or depend on a multi-message semantic ingress queue as part of the redesigned runtime contract.
- [x] Tests cover at least: busy user steer, busy inter-agent inject, idle direct-start behavior, end-of-run race handling, transformer compatibility, and metadata propagation.
- [x] Murmur architecture and package documentation no longer describe the previous Murmur-owned runtime workaround plus `MessageInjector` as the primary mid-run delivery mechanism once the migration is complete.
- [x] Breaking runtime contract changes are allowed where needed to replace the old workaround with a cleaner native integration.

## Scope

### In Scope

- Replacing Murmur's custom busy-agent follow-up delivery path with native `jido_ai` steering where a ReAct run is already active
- Introducing a single ingress coordinator actor per agent session as the only supported delivery-decision boundary
- Refactoring `Runner`, `TellAction`, and related runtime contracts so the normal delivery rule is `ask` when idle and `steer` or `inject` when busy
- Splitting or reducing `MessageInjector` so it only owns Murmur-specific request shaping that upstream steering does not replace
- Defining a jido_ai-aligned ingress input contract for native `steer/3` and `inject/3`
- Allowing only minimal internal race-serialization buffering where needed, without treating it as a Murmur mailbox or inbox abstraction
- Updating tests and architecture documentation to reflect the new runtime model
- Making breaking refactors to message and metadata contracts where they simplify the long-term architecture

### Out of Scope

- Removing request transformers entirely from Murmur
- Replacing Murmur's general ask/await orchestration with a wholly different runtime model
- Preserving the exact internal buffering and envelope contracts used by the previous session-scoped delivery implementation
- Introducing a new first-class Murmur mailbox abstraction for normal message delivery
- Designing a new user-facing chat UX as part of this ticket
- Refactoring unrelated agent features that do not participate in message ingress, follow-up steering, or request shaping