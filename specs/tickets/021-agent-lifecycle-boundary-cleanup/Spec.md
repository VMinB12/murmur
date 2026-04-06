# Spec: Agent Lifecycle Boundary Cleanup

## User Stories

### US-1: One lifecycle policy surface (Priority: P1)

**As a** Murmur maintainer, **I want** the policy for starting, thawing, stopping, and cleaning up agent sessions to live behind one core-owned API, **so that** the reference LiveView does not duplicate runtime lifecycle rules already defined in `jido_murmur`.

**Independent test**: Inspect the workspace lifecycle entry points and verify `WorkspaceLive` no longer contains its own thaw/start or storage-cleanup policy that duplicates core lifecycle helpers.

### US-2: Behavior-preserving boundary cleanup (Priority: P1)

**As a** workspace user, **I want** mount, add-agent, remove-agent, and clear-team flows to behave the same after the cleanup, **so that** consolidating lifecycle ownership does not change runtime behavior.

**Independent test**: Exercise workspace mount, add agent, remove agent, and clear team flows and verify sessions still start, stop, and clean up correctly.

### US-3: Easier host-app reuse (Priority: P2)

**As a** host-application integrator, **I want** a smaller public lifecycle surface in core, **so that** other Phoenix apps can reuse Murmur's session lifecycle behavior without copying demo-owned logic.

**Independent test**: Inspect `jido_murmur` lifecycle helpers and verify the start/stop/cleanup operations needed by the demo are exposed there rather than encoded only inside `WorkspaceLive`.

## Acceptance Criteria

- [ ] `apps/murmur_demo/lib/murmur_web/live/workspace_live.ex` no longer owns its own thaw/start policy for agent sessions.
- [ ] `apps/murmur_demo/lib/murmur_web/live/workspace_live.ex` no longer owns its own checkpoint/thread cleanup policy for agent sessions.
- [ ] Core exposes a smaller explicit lifecycle API used by the demo for mount, add-agent, remove-agent, and clear-team flows.
- [ ] The cleanup preserves current behavior for session startup, teardown, and storage cleanup.
- [ ] Regression tests cover workspace mount, add agent, remove agent, and clear team flows after the boundary cleanup.
- [ ] Architecture documentation is updated if lifecycle ownership descriptions change materially.

## Scope

### In Scope

- Consolidating duplicated lifecycle policy into `jido_murmur`
- Updating the demo LiveView to consume the core lifecycle surface
- Adding or updating tests for lifecycle-sensitive workspace flows
- Updating architecture docs if the ownership boundary changes materially

### Out of Scope

- Redesigning workspace UX or task-board flows
- Changing conversation projection rules
- Reworking visible ingress ownership beyond what lifecycle helpers need