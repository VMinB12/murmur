# Tasks: Multi-Agent Chat Interface

**Input**: Design documents from `/specs/001-multi-agent-chat/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/pubsub.md, quickstart.md

**Tests**: Not explicitly requested in the feature specification. Tests are omitted. Add them later via a separate pass if needed.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Exact file paths included in all descriptions

## Phase 1: Setup

**Purpose**: Project initialization — database schemas, config, and shared infrastructure

- [X] T001 Configure jido_ai model aliases and req_llm API keys in `config/config.exs` and `config/runtime.exs`
- [X] T002 Generate Ecto migration for workspaces table via `mix ecto.gen.migration create_workspaces` and implement in `priv/repo/migrations/*_create_workspaces.exs`
- [X] T003 Generate Ecto migration for agent_sessions table via `mix ecto.gen.migration create_agent_sessions` and implement in `priv/repo/migrations/*_create_agent_sessions.exs` (includes unique index on `[:workspace_id, :display_name]`)
- [X] T004 Generate Ecto migration for messages table via `mix ecto.gen.migration create_messages` and implement in `priv/repo/migrations/*_create_messages.exs` (includes composite index on `[:agent_session_id, :inserted_at]`)
- [X] T005 Run `mix ecto.migrate` to apply all migrations

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared domain modules that ALL user stories depend on. No user story work can begin until this phase is complete.

**⚠️ CRITICAL**: Phases 3–6 are blocked until Phase 2 is complete.

- [X] T006 [P] Create Workspace Ecto schema in `lib/murmur/workspaces/workspace.ex` with fields per data-model.md (id, name, timestamps) and changeset
- [X] T007 [P] Create AgentSession Ecto schema in `lib/murmur/workspaces/agent_session.ex` with fields per data-model.md (id, workspace_id, agent_profile_id, display_name, status, timestamps), changeset with unique constraint on `[:workspace_id, :display_name]`, and `belongs_to :workspace`
- [X] T008 [P] Create Message Ecto schema in `lib/murmur/chat/message.ex` with fields per data-model.md (id, agent_session_id, role, content, sender_name, tool_calls, tool_call_id, metadata, inserted_at), changeset, and `belongs_to :agent_session`
- [X] T009 Create Workspaces context module in `lib/murmur/workspaces.ex` with `create_workspace/1`, `get_workspace!/1`, `list_agent_sessions/1`, `create_agent_session/2` (enforces max 8 per workspace, validates unique display_name), `delete_agent_session/1`
- [X] T010 Create Chat context module in `lib/murmur/chat.ex` with `list_messages/1` (ordered by inserted_at), `create_message/1`, `persist_turn/2` (bulk-insert list of messages for a completed agent turn)
- [X] T011 [P] Create first `Jido.AI.Agent` profile module in `lib/murmur/agents/profiles/general_agent.ex` using `use Jido.AI.Agent, name: "general_agent", model: :fast, tools: [], system_prompt: "You are a helpful assistant."`
- [X] T012 [P] Create second `Jido.AI.Agent` profile module in `lib/murmur/agents/profiles/code_agent.ex` using `use Jido.AI.Agent, name: "code_agent", model: :fast, tools: [], system_prompt: "You are an expert programmer."`
- [X] T013 Create Catalog module in `lib/murmur/agents/catalog.ex` mapping profile IDs to `{agent_module, %{description: ..., color: ...}}` per research decision R8; expose `list_profiles/0`, `get_profile!/1`, `agent_module/1`

**Checkpoint**: Foundation ready — all schemas, contexts, agent profiles, and catalog in place. User story implementation can begin.

---

## Phase 3: User Story 1 — Send a Message and Receive a Streamed Response (Priority: P1) 🎯 MVP

**Goal**: Single-agent chat with token-by-token streaming and per-turn persistence.

**Independent Test**: Open a workspace with one agent, send a message, confirm streamed reply appears and is persisted to the database.

**FRs covered**: FR-001, FR-005, FR-006, FR-007, FR-008, FR-014, FR-016

### Implementation for User Story 1

- [X] T014 [US1] Add workspace and agent session routes to `lib/murmur_web/router.ex` — `live "/workspaces/:id", WorkspaceLive` inside the existing authenticated `live_session`
- [X] T015 [US1] Create WorkspaceLive module in `lib/murmur_web/live/workspace_live.ex` — mount loads workspace + agent sessions + message history from DB, subscribes to PubSub topics per agent session (topic format from contracts/pubsub.md), initializes streams for messages per agent
- [X] T016 [US1] Create WorkspaceLive template in `lib/murmur_web/live/workspace_live.html.heex` — `<Layouts.app>` wrapper, single-agent column with colored header showing display_name/profile/model (FR-016), scrollable message stream with `phx-update="stream"`, text input with `phx-submit="send_message"`, busy indicator (FR-014)
- [X] T017 [US1] Implement `handle_event("send_message", ...)` in WorkspaceLive — creates user Message via Chat context, starts AgentServer via `Murmur.Jido.start_agent/2` if not running, sends message via `AgentModule.ask(pid, user_message)`, broadcasts `{:new_message, ...}` and `{:status_change, ..., :busy}` via PubSub
- [X] T018 [US1] Implement PubSub handlers in WorkspaceLive — `handle_info` for native `%ReAct.Event{kind: :llm_delta}` (stream_insert token into message stream), `{:status_change, ...}` (update busy assign), `{:message_completed, ...}` (finalize assistant message in stream)
- [X] T019 [US1] Implement per-turn persistence hook — after ReAct `request_completed` event, call `Chat.persist_turn/2` to bulk-insert the turn's messages (user message + assistant response + any tool_call/tool_result messages) per research decision R5
- [X] T020 [US1] Implement agent startup and signal-to-PubSub bridge — when starting an AgentServer for a session, configure signal dispatch to forward ReAct events to Phoenix PubSub on the agent's topic (`"workspace:{workspace_id}:agent:{agent_session_id}"`) per research decision R2
- [X] T021 [US1] Wire up auto-scroll JS hook for agent chat columns — create colocated JS hook (`.AutoScroll`) in the template that scrolls to bottom on new stream inserts, with `phx-hook=".AutoScroll"` and `phx-update="ignore"` on the scrollable container

**Checkpoint**: Single-agent chat works end-to-end — user sends a message, tokens stream in real time, history persists to DB.

---

## Phase 4: User Story 2 — Build a Team of Agents in a Workspace (Priority: P2)

**Goal**: Users add/remove multiple agents from a catalog; each agent renders as its own column in a side-by-side layout.

**Independent Test**: Create a workspace, add two agents from catalog, verify both columns appear, send messages to each independently, remove one agent, verify reflow.

**FRs covered**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-018, FR-019

### Implementation for User Story 2

- [X] T022 [US2] Add workspace CRUD routes and index LiveView — add `live "/workspaces", WorkspaceListLive` to router, create `lib/murmur_web/live/workspace_list_live.ex` with create-workspace form and list of existing workspaces
- [X] T023 [US2] Create workspace list template in `lib/murmur_web/live/workspace_list_live.html.heex` — `<Layouts.app>` wrapper, workspace cards with links, create form using `<.form>` and `<.input>`
- [X] T024 [US2] Add agent catalog UI to WorkspaceLive — implement "Add Agent" button/panel that displays available profiles from `Catalog.list_profiles/0`, with a `<.form>` for choosing profile and entering display_name; handle `phx-submit="add_agent"` event
- [X] T025 [US2] Implement `handle_event("add_agent", ...)` in WorkspaceLive — validate unique display_name (FR-019), enforce max 8 agents cap, call `Workspaces.create_agent_session/2`, start AgentServer, subscribe to new PubSub topic, insert agent column into streams
- [X] T026 [US2] Implement `handle_event("remove_agent", ...)` in WorkspaceLive — stop AgentServer via `Murmur.Jido.stop_agent/1`, unsubscribe from PubSub topic, call `Workspaces.delete_agent_session/1`, remove agent column from streams using `stream_delete`
- [X] T027 [US2] Update WorkspaceLive template for multi-agent layout — horizontal flex container for agent columns, each column rendered via a stream keyed by agent_session_id, responsive column widths per agent count, empty state when no agents with guidance to add one (FR-005)
- [X] T028 [US2] Update WorkspaceLive mount to restore all agents — on mount, iterate `Workspaces.list_agent_sessions/1`, start AgentServer for each (if not already running), load message history via `Chat.list_messages/1`, subscribe to all PubSub topics, initialize streams

**Checkpoint**: Multi-agent workspace works — users can create workspaces, add/remove agents, see side-by-side columns, chat with each independently. History restored on refresh.

---

## Phase 5: User Story 3 — Agents Communicate with Each Other (Priority: P3)

**Goal**: Agents use a "tell" tool to send messages to other agents mid-turn, with mid-turn injection for busy agents.

**Independent Test**: Add two agents, prompt Agent A with a task requiring Agent B, verify message appears in Agent B's column from Agent A, Agent B responds.

**FRs covered**: FR-009, FR-010, FR-011, FR-012, FR-015, FR-017

### Implementation for User Story 3

- [X] T029 [US3] Create TellAction in `lib/murmur/agents/tell_action.ex` — `use Jido.Action, name: "tell", schema: Zoi.object(%{target_agent: Zoi.string(), message: Zoi.string()})`, `run/2` resolves target by display_name within the workspace via `Workspaces.find_agent_session_by_name/2`, looks up pid via `Murmur.Jido.whereis/1`, checks hop_count < 5 (FR-015), sends message with sender_name prefix (FR-010)
- [X] T030 [US3] Implement mid-turn pending injection mechanism — add `pending_injections` to agent state schema, implement `request_transformer` callback that calls `GenServer.call(self_pid, :get_and_clear_injections)` between ReAct iterations and merges drained messages into the conversation context per research decision R4
- [X] T031 [US3] Implement idle-agent message delivery in TellAction — when target agent is idle, call `AgentModule.ask(target_pid, message)` to immediately trigger processing (FR-011); when target is busy, append to `pending_injections` for mid-turn injection (FR-012)
- [X] T032 [US3] Add TellAction as a tool to all agent profile modules — update `lib/murmur/agents/profiles/general_agent.ex` and `lib/murmur/agents/profiles/code_agent.ex` to include `Murmur.Agents.TellAction` in their `tools:` list
- [X] T033 [US3] Implement user-message-to-busy-agent injection — update `handle_event("send_message", ...)` in WorkspaceLive to detect busy status and append to `pending_injections` instead of calling `ask/2`, matching tell behavior (FR-017)
- [X] T034 [US3] Add `find_agent_session_by_name/2` to Workspaces context in `lib/murmur/workspaces.ex` — query AgentSession by workspace_id + display_name for TellAction routing
- [X] T035 [US3] Handle tell-to-removed-agent edge case — in TellAction `run/2`, return `{:error, "Agent not found"}` when target pid is nil; the ReAct runtime surfaces this as a tool error to the calling agent

**Checkpoint**: Inter-agent communication works — agents can "tell" each other mid-turn, messages inject into busy agents, hop depth is limited, graceful failure on removed targets.

---

## Phase 6: User Story 4 — Reconnect and Resume After Disconnect (Priority: P4)

**Goal**: Browser disconnect does not interrupt agents; reconnect restores full state and resumes streaming.

**Independent Test**: Start an agent response, disconnect WebSocket, wait, reconnect — verify full response visible and still-running agents continue streaming.

**FRs covered**: FR-013, FR-013a, FR-013b

### Implementation for User Story 4

- [X] T036 [US4] Verify server-side autonomy — ensure AgentServer processes are not linked to LiveView pids; confirm agents continue executing when the LiveView process terminates (FR-013a). This should already work via Jido's supervision tree but must be explicitly verified.
- [X] T037 [US4] Implement reconnect state rehydration in WorkspaceLive mount — on both initial mount and reconnect, call `Jido.AgentServer.state/1` for each agent session to get current in-memory history and status (idle/busy) per research decision R6; use this as the authoritative state, falling back to DB history only if AgentServer is not running
- [X] T038 [US4] Implement reconnect PubSub re-subscription — on mount, re-subscribe to all active agent session PubSub topics; if an agent's status is `:busy`, incoming `:llm_delta` events will resume streaming to the browser immediately (FR-013b)
- [X] T039 [US4] Handle agent completed during disconnect — if `Jido.AgentServer.state/1` shows the agent is now idle but has messages newer than what was persisted, persist any unsaved turn and display the complete history

**Checkpoint**: Reconnect works seamlessly — agents are autonomous, state restores from GenServer, streaming resumes mid-response.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that span multiple user stories

- [X] T040 [P] Add empty workspace state UI in WorkspaceLive template — show guidance to add an agent when no agents exist
- [X] T041 [P] Add loading/skeleton states for agent columns during initial mount
- [X] T042 [P] Add smooth CSS transitions for agent column add/remove reflow using Tailwind v4 classes
- [X] T043 Run `mix precommit` (format + compile + credo + dialyzer) and fix all warnings/errors
- [X] T044 Validate feature end-to-end using quickstart.md verification steps

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 (migrations must exist before schemas reference tables)
- **Phase 3 (US1)**: Depends on Phase 2 — first user story, MVP
- **Phase 4 (US2)**: Depends on Phase 2 + Phase 3 (multi-agent layout extends single-agent WorkspaceLive)
- **Phase 5 (US3)**: Depends on Phase 4 (tell requires multiple agents in workspace) + Phase 3 (agents must be able to chat)
- **Phase 6 (US4)**: Depends on Phase 3 (streaming must work to test reconnect); can be done in parallel with Phase 5
- **Phase 7 (Polish)**: Depends on all desired user stories being complete

### User Story Dependencies

- **US1 (P1)**: Foundational only — no other story dependency
- **US2 (P2)**: Extends US1's WorkspaceLive to support multiple columns
- **US3 (P3)**: Requires US2 (multiple agents must exist for "tell") + US1 (agents must chat)
- **US4 (P4)**: Requires US1 (streaming must work); independent of US2/US3

### Within Each User Story

- Schemas/context functions before LiveView
- LiveView module before template
- Core event handlers before edge case handling
- PubSub wiring before UI polish

### Parallel Opportunities

**Phase 2** (after Phase 1):
- T006, T007, T008 (all schemas) can run in parallel
- T011, T012 (agent profiles) can run in parallel with schemas
- T009, T010 (contexts) depend on their respective schemas

**Phase 3** (US1):
- T014 (routes) and T020 (signal bridge) can start in parallel
- T015–T019 are sequential (LiveView → template → handlers → PubSub → persistence)

**Phase 5 + Phase 6** can run in parallel once Phase 4 is complete:
- US3 (tell) and US4 (reconnect) are independent of each other

**Phase 7**:
- T040, T041, T042 are all parallel (independent UI polish)

---

## Parallel Example: Phase 2 (Foundational)

```
Batch 1 (parallel — all schema files):
  T006: Workspace schema in lib/murmur/workspaces/workspace.ex
  T007: AgentSession schema in lib/murmur/workspaces/agent_session.ex
  T008: Message schema in lib/murmur/chat/message.ex
  T011: GeneralAgent profile in lib/murmur/agents/profiles/general_agent.ex
  T012: CodeAgent profile in lib/murmur/agents/profiles/code_agent.ex

Batch 2 (after schemas):
  T009: Workspaces context in lib/murmur/workspaces.ex
  T010: Chat context in lib/murmur/chat.ex
  T013: Catalog module in lib/murmur/agents/catalog.ex
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (config + migrations)
2. Complete Phase 2: Foundational (schemas, contexts, profiles, catalog)
3. Complete Phase 3: User Story 1 (single-agent streaming chat)
4. **STOP and VALIDATE**: Send a message, see streaming, verify persistence
5. Deploy/demo if ready — this is a working single-agent chat

### Incremental Delivery

1. Setup + Foundational → Foundation ready
2. Add US1 → Single-agent chat works → **MVP!**
3. Add US2 → Multi-agent workspace → Team construction works
4. Add US3 → Inter-agent tell → Agents collaborate
5. Add US4 → Reconnect → Resilient sessions
6. Polish → Production-quality UI

### Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] labels map tasks to specific user stories for traceability
- Each user story checkpoint is independently verifiable
- Commit after each task or logical batch
- Run `mix precommit` periodically, not just at the end
