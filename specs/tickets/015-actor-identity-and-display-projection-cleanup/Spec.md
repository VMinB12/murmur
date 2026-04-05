# Spec: Actor Identity And Display Projection Cleanup

## User Stories

### US-1: Explicit actor semantics across runtime and UI (Priority: P1)

**As a** Murmur maintainer, **I want** the system to represent the current actor, the origin actor, and the UI-facing display actor as distinct concepts, **so that** one field no longer carries multiple meanings across runtime context, ingress metadata, and rendered messages.

**Independent test**: Inspect runtime context, persisted message metadata, and rendered UI message data for one human-to-agent and one agent-to-agent interaction, and verify each layer exposes explicit actor semantics without relying on one overloaded sender field.

### US-2: Canonical display-message projection (Priority: P1)

**As a** frontend and package maintainer, **I want** UI consumers to receive one canonical display-message shape, **so that** rendering code does not need to repair mixed payload formats, infer actor identity, or special-case legacy message shapes.

**Independent test**: Project the same conversation through the shared UI projection path and verify the resulting display messages can be rendered without atom-versus-string key fallback or content-based sender inference.

### US-3: Presentation-owned sender labels (Priority: P1)

**As a** host-application developer, **I want** user-facing sender labels such as human, agent, or system wording to be chosen at the presentation edge, **so that** product-specific wording can change without rewriting runtime metadata contracts.

**Independent test**: Change the presentation wording for human-originated messages in one host-facing rendering path and verify the underlying actor metadata and display-message projection contract remain unchanged.

### US-4: Consistent styling and grouping without string heuristics (Priority: P2)

**As a** workspace user, **I want** message grouping, coloring, and labeling to be driven by canonical actor semantics rather than raw display strings, **so that** the interface stays consistent even when host apps customize labels or when messages originate from different actor types.

**Independent test**: Render a mixed conversation containing human, agent, and system-originated messages with customized display labels and verify grouping and styling still behave consistently.

### US-5: Cleaner package boundary before publication (Priority: P1)

**As a** package maintainer, **I want** Murmur to remove identity-repair logic and transitional message-shape compatibility behavior before the package boundary hardens, **so that** Hex consumers inherit one clear actor and display contract instead of legacy cleanup code.

**Independent test**: Review the runtime-to-UI boundary after implementation and verify there is one primary actor model and one primary display-message model in the affected slice, with no remaining compatibility path for the removed identity repair behavior.

## Acceptance Criteria

- [ ] Runtime-facing metadata distinguishes the current actor from the origin actor using explicit semantics instead of one overloaded sender field.
- [ ] UI-facing message projection exposes one canonical display-message shape for human, agent, and system-originated messages.
- [ ] The canonical display-message shape includes the actor information required for labeling, grouping, and styling without requiring content parsing or mixed payload-key fallback.
- [ ] `UITurn` or the equivalent shared UI projection boundary no longer infers actor identity from formatted message text.
- [ ] `UITurn` or the equivalent shared UI projection boundary no longer depends on atom-versus-string payload fallback for the cleaned-up message path.
- [ ] User-facing labels such as human or agent wording are selected by presentation helpers or host-facing rendering code rather than being treated as the runtime source of truth.
- [ ] Host applications can customize displayed human-facing sender wording without changing the runtime actor contract.
- [ ] Message coloring, grouping, and similar rendering behavior are driven by canonical actor semantics rather than raw string comparisons against display labels like `"You"`.
- [ ] The cleaned-up actor and display contract is applied consistently across at least the shared chat-message component and the split/unified workspace projections.
- [ ] Existing identity semantics needed for observability, causation, and inter-agent context remain available after the refactor, but under clearer field meanings.
- [ ] Architecture documentation reflects the canonical actor-identity boundary and canonical display-message projection boundary.
- [ ] Tests cover at least one human-originated path, one inter-agent path, and one customized presentation-label path.

## Scope

### In Scope

- Defining one explicit actor-identity boundary for runtime and UI consumers
- Defining one canonical display-message projection model for UI rendering
- Removing sender-identity inference from message text in the cleaned-up projection path
- Removing mixed payload-key fallback behavior where it only exists to support the retired identity/display ambiguity
- Moving sender-label wording decisions to presentation-owned helpers or equivalent host-facing rendering boundaries
- Aligning shared chat rendering behavior so styling and grouping depend on canonical actor semantics
- Updating documentation and tests to match the new actor and display contract
- Making breaking internal or package-boundary changes where needed to simplify the unpublished contract

### Out of Scope

- Redesigning the general ingress contract cleaned up in ticket 014
- Reworking the session coordination or active-run steering model introduced in tickets 012 and 013
- Changing the overall visual design of the chat UI beyond what is required to consume the new canonical display model
- Introducing a new end-user feature unrelated to actor identity or display-message projection
- Preserving backward compatibility for the removed identity-repair logic in unpublished package surfaces