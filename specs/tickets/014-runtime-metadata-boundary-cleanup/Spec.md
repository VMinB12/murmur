# Spec: Runtime Metadata Boundary Cleanup

## User Stories

### US-1: Configurable inter-agent safety metadata (Priority: P1)

**As a** Murmur maintainer, **I want** inter-agent hop depth to be propagated through the same canonical runtime metadata path as other delivery metadata and enforced against a configurable hop-limit policy, **so that** the loop-prevention rule is actually enforced across chained tells without being hardcoded into the first published package surface.

**Independent test**: Trigger a chained inter-agent workflow and verify hop depth increments across each tell until the configured limit rejects the next tell.

### US-2: Graceful hop-limit feedback (Priority: P1)

**As a** package maintainer, **I want** tell attempts that hit the hop limit to return an informative agent-visible outcome instead of crashing out, **so that** agents can adapt to routing policy limits without turning a normal safety boundary into a runtime failure mode.

**Independent test**: Trigger a tell that exceeds the configured hop limit and verify the calling agent receives a clear explanation that the hop limit was reached while the run and agent process remain healthy.

### US-3: One metadata source of truth after ingress (Priority: P1)

**As a** Murmur maintainer, **I want** tool context and downstream runtime metadata to be projected from canonical ingress metadata rather than rebuilt ad hoc in multiple modules, **so that** new routing or observability metadata does not require duplicated plumbing.

**Independent test**: Deliver canonical programmatic input containing workflow metadata and verify runner, tool execution context, and downstream actions all observe the same values.

### US-4: Shared programmatic delivery pattern (Priority: P2)

**As a** Murmur maintainer, **I want** programmatic producers to use a shared delivery helper or equivalent common path for visible inbound message broadcast plus ingress delivery, **so that** task notifications, tells, and similar follow-up producers do not drift in metadata shape.

**Independent test**: Compare at least two programmatic producer paths and verify they emit consistent inbound message metadata and canonical ingress input fields.

### US-5: Clean publishable runtime boundary (Priority: P1)

**As a** package maintainer, **I want** the runtime structures around ingress, projected metadata, and visible programmatic delivery to be aligned before the first package release, **so that** Murmur does not publish legacy paths, fallback readers, or transitional compatibility shims as part of its public or de facto runtime contract.

**Independent test**: Inspect the ingress-adjacent runtime after implementation and verify one canonical structure exists per concept, with no legacy compatibility path or fallback branch remaining for the cleaned-up metadata flow.

## Acceptance Criteria

- [ ] Inter-agent `hop_count` is propagated through the canonical ingress metadata path and reaches downstream action context correctly.
- [ ] The maximum tell hop limit is configurable through Murmur configuration with a documented default.
- [ ] The configured tell hop limit is enforced across chained inter-agent delivery, not only at the originating tell call.
- [ ] When tell is blocked by hop policy, the calling agent receives an informative tool-visible outcome explaining that the hop limit was reached, and the agent run does not crash as a result.
- [ ] Runner-owned tool context is projected from canonical ingress metadata through one explicit runtime boundary rather than selectively rebuilt from separate ad hoc fields.
- [ ] Duplicated ref lookup and metadata assembly helpers in the ingress-adjacent runtime are removed or clearly consolidated.
- [ ] At least the `TellAction` and task-assignment notification path use a shared programmatic delivery pattern or one equivalent common helper.
- [ ] Runtime structures that represent the same concept across ingress, projected tool context, and visible programmatic delivery are aligned instead of being translated through multiple partially overlapping shapes.
- [ ] No legacy ingress-adjacent compatibility path, fallback branch, or transitional metadata reader remains in scope for the cleaned-up runtime path once this ticket is complete.
- [ ] Architecture documentation reflects that canonical ingress metadata is the source of truth for runtime delivery metadata.
- [ ] Tests cover hop-depth propagation, tool-context projection, and at least one shared programmatic delivery path.

## Scope

### In Scope

- Fixing inter-agent hop-depth propagation through the post-ingress runtime path
- Making the tell hop-limit policy configurable and documenting the default behavior
- Surfacing hop-limit exhaustion as an informative agent-visible outcome instead of a crash-shaped runtime failure
- Defining one explicit projection boundary from canonical ingress metadata into action-visible runtime context
- Consolidating duplicated metadata lookup and projection helpers in ingress-adjacent modules
- Aligning ingress-adjacent runtime data structures where they represent the same delivery or metadata concept
- Simplifying programmatic delivery paths where that simplification supports metadata consistency
- Removing legacy paths, fallback readers, and transitional compatibility behavior in the cleaned-up runtime metadata flow
- Updating architecture documentation to match the resulting runtime rule

### Out of Scope

- Reworking the ingress coordinator ownership model introduced in ticket 012
- Changing the Phoenix session grouping model already being handled by ticket 013
- Introducing workspace-wide routing quotas or broader rate-limiting policy beyond the configurable per-tell hop limit
- Redesigning general PubSub message rendering semantics in the UI
- Replacing Murmur's use of `source` and `refs` with a different top-level ingress contract
- Adding compatibility shims to preserve pre-cleanup metadata structures for unpublished package consumers