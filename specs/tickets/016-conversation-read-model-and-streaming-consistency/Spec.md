# Spec: Conversation Read Model And Streaming Consistency

## User Stories

### US-1: Consistent live and completed turn rendering (Priority: P1)

**As a** workspace user, **I want** an in-progress agent turn to show the same tool-call and thinking structure that I see after completion or refresh, **so that** the UI does not appear to hide work until the run is over.

**Independent test**: Trigger an agent response that performs at least one tool call and verify the live UI shows pending and completed tool-call state before the final assistant turn is committed.

### US-2: Timing-safe stream completion (Priority: P1)

**As a** Murmur maintainer, **I want** stream signals and completion handling to remain consistent even when PubSub delivery order varies across topics, **so that** late but valid tool-call signals are not silently discarded.

**Independent test**: Simulate `murmur.message.completed` arriving before `ai.llm.response` or `ai.tool.result` and verify the final visible turn still contains the expected tool-call data without relying on a manual refresh.

### US-3: One package-owned conversation read boundary (Priority: P1)

**As a** package maintainer, **I want** one canonical read model for conversation rendering, **so that** live rendering, persisted refresh, and helper APIs do not each maintain their own message hydration logic.

**Independent test**: Inspect the code paths used by `WorkspaceLive`, `WorkspaceState`, and `AgentHelper` and verify they all consume the same package-owned conversation reduction/projection API.

### US-4: Explicit streaming lifecycle semantics (Priority: P2)

**As a** frontend maintainer, **I want** pending tool calls, running tool calls, completed tool calls, and finalized assistant output to have explicit state transitions, **so that** rendering logic does not infer lifecycle from partial signal timing.

**Independent test**: Drive a run through thinking, tool-call start, tool result, and assistant completion phases and verify the rendered state transitions are deterministic and independently testable.

## Acceptance Criteria

- [ ] Live and completed conversation rendering use one canonical read model or one clearly shared package-owned reduction/projection boundary.
- [ ] Tool-call state visible after completion is also visible during live rendering whenever the corresponding stream signals have been emitted.
- [ ] The UI no longer drops valid tool-call or assistant-turn state solely because `murmur.message.completed` arrived before a related stream signal on a different PubSub topic.
- [ ] `AgentHelper` and demo-owned workspace state no longer duplicate the same thread-loading and projection logic.
- [ ] Live streaming handles explicit tool lifecycle semantics rather than depending only on a subset of forwarded signals.
- [ ] Regression tests cover at least one out-of-order signal scenario involving `murmur.message.completed` and a later `ai.llm.response` or `ai.tool.result`.
- [ ] Regression tests cover at least one end-to-end tool-call path where the live UI and refreshed UI show equivalent tool-call information.
- [ ] Architecture documentation reflects the canonical conversation read boundary if the implementation changes package ownership or rendering flow.

## Scope

### In Scope

- Analyzing and fixing the split between live stream rendering and persisted conversation rendering
- Defining a canonical conversation read model or equivalent shared reduction/projection boundary
- Fixing tool-call visibility gaps caused by signal ordering and transient stream-state handling
- Consolidating duplicated thread-loading and projection logic where it directly affects conversation rendering consistency
- Adding regression coverage for out-of-order signals and live-versus-refresh equivalence

### Out of Scope

- Redesigning the general visual style of chat surfaces
- Changing Murmur's actor-identity model introduced in ticket 015
- Reworking unrelated artifact or task-board rendering flows except where they share the same conversation read boundary
- Redesigning the overall PubSub topology beyond what is needed for correct conversation rendering semantics