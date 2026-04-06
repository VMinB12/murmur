# Spec: Conversation Read Model And Streaming Consistency

## User Stories

### US-1: Consistent live and completed turn rendering (Priority: P1)

**As a** workspace user, **I want** an in-progress agent turn to show the same tool-call and thinking structure that I see after completion or refresh, **so that** the UI does not appear to hide work until the run is over.

**Independent test**: Trigger an agent response that performs at least one tool call and verify the live UI shows pending and completed tool-call state before the final assistant turn is committed.

### US-2: Timing-safe stream completion (Priority: P1)

**As a** Murmur maintainer, **I want** stream signals and completion handling to remain consistent even when PubSub delivery order varies across topics, **so that** late but valid tool-call signals are not silently discarded.

**Independent test**: Simulate `murmur.message.completed` arriving before `ai.llm.response` or `ai.tool.result` and verify the final visible turn still contains the expected tool-call data without relying on a manual refresh.

### US-3: One core-owned conversation projector and UI contract (Priority: P1)

**As a** package maintainer, **I want** `jido_murmur` to own canonical conversation projection and the UI-facing update contract, **so that** LiveViews and helper APIs do not each reduce raw `ai.*` signals or maintain their own message hydration logic.

**Independent test**: Inspect the code paths used by `WorkspaceLive`, `WorkspaceState`, and `AgentHelper` and verify they all consume the same package-owned conversation projector or snapshot/update API instead of reducing raw `ai.*` rendering events directly.

### US-4: Stable turn identity and explicit lifecycle semantics (Priority: P1)

**As a** frontend maintainer, **I want** pending tool calls, running tool calls, completed tool calls, and finalized assistant output to be tied to one stable turn identity with explicit lifecycle state transitions, **so that** rendering logic does not infer lifecycle from partial signal timing or session-level heuristics.

**Independent test**: Drive a run through thinking, tool-call start, tool result, and assistant completion phases and verify the rendered state transitions remain deterministic and associated with one turn identity across the entire run.

## Acceptance Criteria

- [x] Live and completed conversation rendering use one canonical read model owned by `jido_murmur`.
- [x] Connected UIs consume a Murmur-owned conversation snapshot or update contract rather than rendering directly from raw `ai.*` lifecycle signals.
- [x] Tool-call state visible after completion is also visible during live rendering whenever the corresponding stream signals have been emitted.
- [x] The UI no longer drops valid tool-call or assistant-turn state solely because `murmur.message.completed` arrived before a related stream signal on a different PubSub topic.
- [x] Every conversation-affecting fact reduced into canonical state is associated with a stable turn identity, and tool lifecycle facts preserve tool call identity where available.
- [x] `AgentHelper` and demo-owned workspace state no longer duplicate the same thread-loading and projection logic.
- [x] Raw `ai.*` signals may remain available for observability, but they are no longer the UI rendering contract.
- [x] Live streaming handles explicit tool lifecycle semantics rather than depending only on a subset of forwarded signals.
- [x] Regression tests cover at least one out-of-order signal scenario involving `murmur.message.completed` and a later `ai.llm.response` or `ai.tool.result`.
- [x] Regression tests cover at least one end-to-end tool-call path where the live UI and refreshed UI show equivalent tool-call information.
- [x] Regression tests cover at least one reconnect or fresh-mount path where canonical conversation state matches the live in-progress turn after reconciliation.
- [x] Architecture documentation reflects the canonical conversation read boundary if the implementation changes package ownership or rendering flow.

## Scope

### In Scope

- Analyzing and fixing the split between live stream rendering and persisted conversation rendering
- Defining a canonical conversation read model or equivalent shared reduction/projection boundary
- Defining one Murmur-owned conversation snapshot or update contract for UI consumers
- Fixing tool-call visibility gaps caused by signal ordering and transient stream-state handling
- Associating conversation-affecting facts with stable turn identity even when Murmur must attach that identity itself at the projector boundary
- Consolidating duplicated thread-loading and projection logic where it directly affects conversation rendering consistency
- Adding regression coverage for out-of-order signals and live-versus-refresh equivalence

### Out of Scope

- Redesigning the general visual style of chat surfaces
- Changing Murmur's actor-identity model introduced in ticket 015
- Reworking unrelated artifact or task-board rendering flows except where they share the same conversation read boundary
- Redesigning the overall PubSub topology beyond what is needed for correct conversation rendering semantics