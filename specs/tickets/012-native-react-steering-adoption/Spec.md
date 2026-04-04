# Spec: Native ReAct Steering Adoption

## User Stories

### US-1: Native active-run follow-up delivery (Priority: P1)

**As a** Murmur maintainer, **I want** follow-up input sent to a currently running ReAct loop to use native `jido_ai` steering controls, **so that** Murmur stops owning a custom mid-run message injection mechanism.

**Independent test**: Start a long-running agent turn, send a direct human follow-up and an inter-agent follow-up while the run is active, and verify they reach the active run through native steering rather than through a custom queue drain in `MessageInjector`.

### US-2: Preserve idle wake-up and no-drop delivery semantics (Priority: P1)

**As a** workspace user, **I want** messages to still wake idle agents and survive active-run race boundaries, **so that** adopting native steering does not make delivery less reliable than Murmur's current behavior.

**Independent test**: Send input to an idle agent and verify a new run starts. Then send input at the end of an active run and verify the message either lands in that run or is retried as a new run instead of being silently dropped.

### US-3: Keep Murmur-specific request shaping independent from follow-up delivery (Priority: P1)

**As a** package maintainer, **I want** team instructions and package-specific context injection to remain supported independently of follow-up routing, **so that** Murmur can adopt native steering without losing dynamic prompt enrichment.

**Independent test**: Verify a general agent still receives workspace team instructions and a SQL agent still receives schema context, while busy-agent follow-up delivery no longer depends on `MessageInjector` draining queued messages.

### US-4: Preserve metadata and observability across the new control path (Priority: P1)

**As a** developer debugging multi-agent behavior, **I want** follow-up messages delivered through native steering to preserve interaction and origin metadata, **so that** traces, causation, and workspace conversation grouping remain trustworthy after the refactor.

**Independent test**: Inject a follow-up input with Murmur interaction metadata and verify the receiving run retains stable correlation data for conversation grouping and trace linking.

### US-5: Reduce Murmur-owned runtime surface area (Priority: P2)

**As a** Murmur maintainer, **I want** the codebase to remove or narrow custom queueing and transformer logic that only exists to emulate missing upstream behavior, **so that** future upgrades follow native `jido_ai` capabilities instead of preserving historical workarounds.

**Independent test**: Inspect the runtime path and verify that Murmur no longer uses a custom busy-agent queue drain as the primary mechanism for active-run follow-up input, and that any remaining Murmur-owned queueing is explicitly limited to pre-run ingress or documented fallback behavior.

## Acceptance Criteria

- [ ] Busy human follow-up input is routed through native `steer/3`.
- [ ] Busy inter-agent or programmatic follow-up input is routed through native `inject/3`.
- [ ] Murmur only attempts native steering when a ReAct run is active, and uses current-run correlation when available to avoid attaching input to the wrong run.
- [ ] If a native steering call rejects because the agent is idle or the active run has just ended, Murmur falls back to starting a new run instead of silently dropping the input.
- [ ] Murmur no longer depends on `MessageInjector` to drain busy-agent follow-up messages into request messages.
- [ ] Dynamic team instructions remain injected for agents that require workspace context.
- [ ] SQL schema injection remains available for the SQL agent or any equivalent package-specific request-shaping path.
- [ ] Murmur defines and documents a control-input contract that maps its metadata needs onto upstream steering fields, including how `interaction_id`, `kind`, `sender_name`, and `sender_trace_id` are preserved.
- [ ] Cross-agent `tell` keeps its fire-and-forget semantics while still waking idle targets and steering busy targets in place.
- [ ] Active-run follow-up input remains visible to Murmur's observability and conversation-grouping systems with stable causation and interaction metadata.
- [ ] Tests cover at least: busy user steer, busy inter-agent inject, idle fallback, end-of-run race handling, transformer compatibility, and metadata propagation.
- [ ] Murmur architecture and package documentation no longer describe `PendingQueue` plus `MessageInjector` as the primary mid-run delivery mechanism once the migration is complete.
- [ ] Breaking runtime contract changes are allowed where needed to replace the old workaround with a cleaner native integration.

## Scope

### In Scope

- Replacing Murmur's custom busy-agent follow-up delivery path with native `jido_ai` steering where a ReAct run is already active
- Refactoring `Runner`, `TellAction`, and related runtime contracts so idle and busy delivery paths are explicit
- Splitting or reducing `MessageInjector` so it only owns Murmur-specific request shaping that upstream steering does not replace
- Defining a new control-input metadata contract for native `steer/3` and `inject/3`
- Updating tests and architecture documentation to reflect the new runtime model
- Making breaking refactors to message and metadata contracts where they simplify the long-term architecture

### Out of Scope

- Removing request transformers entirely from Murmur
- Replacing Murmur's general ask/await orchestration with a wholly different runtime model
- Preserving the exact internal queue and envelope contracts used by the current PendingQueue implementation
- Designing a new user-facing chat UX as part of this ticket
- Refactoring unrelated agent features that do not participate in message ingress, follow-up steering, or request shaping