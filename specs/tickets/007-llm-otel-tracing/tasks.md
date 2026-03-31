# Tasks: LLM OpenTelemetry Tracing

**Input**: Design documents from `/specs/007-llm-otel-tracing/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, quickstart.md

**Tests**: Tests ARE included — the feature already has 17 existing tests and the spec requires test coverage for the new functionality.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Umbrella app**: `apps/jido_murmur/`, `apps/murmur_demo/`, `config/`
- Handler: `apps/jido_murmur/lib/jido_murmur/telemetry/req_llm_tracer.ex`
- Tests: `apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Enable raw telemetry payloads and validate existing handler still works

- [x] T001 Add `config :req_llm, telemetry: [payloads: :raw]` to `config/config.exs`
- [x] T002 [P] Add `config :req_llm, telemetry: [payloads: :none]` to `config/prod.exs` to disable raw payloads in production
- [x] T003 Verify existing 17 tests still pass after config change by running `mix test apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs`

**Checkpoint**: Config in place, existing functionality preserved

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Add message flattening helpers and ETS schema expansion that all user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T004 Implement `flatten_input_messages/1` private function in `apps/jido_murmur/lib/jido_murmur/telemetry/req_llm_tracer.ex` — takes a list of message maps from `request_payload`, returns a flat map of OpenInference attributes (`"llm.input_messages.{N}.message.role"` → role, `"llm.input_messages.{N}.message.content"` → content text)
- [x] T005 [P] Implement `flatten_output_messages/1` private function in `apps/jido_murmur/lib/jido_murmur/telemetry/req_llm_tracer.ex` — takes a list of output message maps from `response_payload`, returns a flat map of OpenInference attributes (`"llm.output_messages.{N}.message.role"` → role, `"llm.output_messages.{N}.message.content"` → content text)
- [x] T006 [P] Implement `flatten_tool_calls/2` private function in `apps/jido_murmur/lib/jido_murmur/telemetry/req_llm_tracer.ex` — takes a message index and a list of tool call maps, returns flat attributes (`"llm.{input|output}_messages.{N}.message.tool_calls.{M}.tool_call.function.name"` and `".arguments"` as JSON string)
- [x] T007 [P] Implement `extract_content/1` private helper in `apps/jido_murmur/lib/jido_murmur/telemetry/req_llm_tracer.ex` — normalizes message content from either plain string or `[%{type: :text, text: "..."}]` content part list to a single string
- [x] T008 [P] Implement `extract_input_value/1` and `extract_output_value/1` private functions in `apps/jido_murmur/lib/jido_murmur/telemetry/req_llm_tracer.ex` — extract the last user message content and last assistant message content respectively for `input.value` and `output.value` attributes
- [x] T009 Expand ETS entry schema in `apps/jido_murmur/lib/jido_murmur/telemetry/req_llm_tracer.ex` — change ETS value from `{request_id, span_ctx}` to `{request_id, span_ctx, agent_context}` where `agent_context` is a map of `%{workspace_id, display_name}` or `nil`, to support cross-process session/agent enrichment
- [x] T010 Write unit tests for `flatten_input_messages/1` in `apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs` — test with: single user message, multi-message conversation (system + user + assistant), empty message list, messages with content part lists
- [x] T011 [P] Write unit tests for `flatten_output_messages/1` in `apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs` — test with: single assistant response, assistant response with tool calls, empty output
- [x] T012 [P] Write unit tests for `flatten_tool_calls/2` in `apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs` — test with: single tool call, multiple tool calls, tool call with map arguments (JSON encoded)
- [x] T013 [P] Write unit test for `extract_content/1` in `apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs` — test with: plain string, content part list, nil content, empty string

**Checkpoint**: Foundation ready — all flattening helpers tested and ETS schema expanded

---

## Phase 3: User Story 1 — View LLM Conversation Content (Priority: P1) 🎯 MVP

**Goal**: Every LLM trace shows input messages with roles and content, and the output response

**Independent Test**: Send a message to an agent, open Phoenix at localhost:6006, click the trace, verify input/output messages are visible with roles and content

### Tests for User Story 1

- [x] T014 [US1] Write integration test in `apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs` — simulate a `:start` event with `request_payload` containing `messages: [%{role: "system", content: "You are helpful"}, %{role: "user", content: "Hello"}]`, verify span attributes include `"llm.input_messages.0.message.role" => "system"`, `"llm.input_messages.0.message.content" => "You are helpful"`, `"llm.input_messages.1.message.role" => "user"`, `"llm.input_messages.1.message.content" => "Hello"`, and `"input.value" => "Hello"`

### Implementation for User Story 1

- [x] T015 [US1] Update `handle_event([:req_llm, :request, :start], ...)` in `apps/jido_murmur/lib/jido_murmur/telemetry/req_llm_tracer.ex` — extract `messages` from `metadata[:request_payload]`, call `flatten_input_messages/1`, merge resulting attributes into span start attributes, add `"input.value"` from `extract_input_value/1`
- [x] T016 [US1] Update `handle_event([:req_llm, :request, :stop], ...)` in `apps/jido_murmur/lib/jido_murmur/telemetry/req_llm_tracer.ex` — extract output messages from `metadata[:response_payload]`, call `flatten_output_messages/1`, merge into stop attributes, add `"output.value"` from `extract_output_value/1`
- [x] T017 [US1] Write end-to-end test in `apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs` — simulate full start→stop cycle with `request_payload` containing messages and `response_payload` containing assistant response, verify both input and output message attributes are set on the span

**Checkpoint**: Traces now show full conversation content. This is the MVP — independently verifiable in Phoenix UI.

---

## Phase 4: User Story 6 — Trace Streaming LLM Calls Reliably (Priority: P1)

**Goal**: Streaming calls produce identical trace richness to non-streaming — input messages on start, output + tokens on stop, even across processes

**Independent Test**: Send a streaming message to an agent, verify trace has complete output text and token counts (not partial or empty)

### Tests for User Story 6

- [x] T018 [US6] Write cross-process streaming test in `apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs` — fire `:start` event with `request_payload` (messages) in process A, fire `:stop` event with `response_payload` (assistant response + tokens) in process B (spawned task), verify span has both input message attributes (from start) and output message attributes (from stop)

### Implementation for User Story 6

- [x] T019 [US6] Ensure `request_payload` messages are stored alongside span context in ETS during `:start` handler in `apps/jido_murmur/lib/jido_murmur/telemetry/req_llm_tracer.ex` — the input message attributes are set at start time on the span, and the span_ctx is passed to stop via ETS, so stop only needs to add output attributes. Verify `:start` handler sets input attributes on `span_ctx` before storing in ETS
- [x] T020 [US6] Write test for streaming call that fails mid-stream in `apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs` — fire `:start` event in process A, fire `:exception` event in process B, verify span has input message attributes and error status with error message

**Checkpoint**: Streaming traces are complete and reliable — identical attribute richness to non-streaming

---

## Phase 5: User Story 2 — Track Token Usage and Cost (Priority: P2)

**Goal**: Every trace shows prompt tokens, completion tokens, and total token count

**Independent Test**: View a trace in Phoenix, verify token counts are visible and match model provider values

### Implementation for User Story 2

- [x] T021 [US2] Verify token count attributes in `handle_event([:req_llm, :request, :stop], ...)` in `apps/jido_murmur/lib/jido_murmur/telemetry/req_llm_tracer.ex` — confirm existing `llm.token_count.prompt`, `llm.token_count.completion`, `llm.token_count.total`, `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens` are correctly extracted from `metadata[:usage]`. This is largely already implemented — audit and fix any gaps
- [x] T022 [US2] Write test in `apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs` verifying token counts — simulate stop event with `usage: %{input_tokens: 150, output_tokens: 80}`, verify all five token attributes are correctly set including total = 230

**Checkpoint**: Token usage visible on all traces

---

## Phase 6: User Story 3 — Inspect Tool Calls (Priority: P2)

**Goal**: Tool call names and arguments visible in both input and output message attributes

**Independent Test**: Trigger an agent conversation with tool use, view trace, verify tool calls appear

### Tests for User Story 3

- [x] T023 [US3] Write test for output tool calls in `apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs` — simulate stop event with `response_payload` containing an assistant message with `tool_calls: [%{function: %{name: "get_weather", arguments: %{city: "Amsterdam"}}}]`, verify `"llm.output_messages.0.message.tool_calls.0.tool_call.function.name" => "get_weather"` and `".arguments" => "{\"city\":\"Amsterdam\"}"` (JSON encoded)
- [x] T024 [P] [US3] Write test for input tool result messages in `apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs` — simulate start event with `request_payload` containing a tool role message `%{role: "tool", content: "{\"temp\": 18}", name: "get_weather"}`, verify `"llm.input_messages.N.message.role" => "tool"` and content is set

### Implementation for User Story 3

- [x] T025 [US3] Integrate `flatten_tool_calls/2` into `flatten_input_messages/1` and `flatten_output_messages/1` in `apps/jido_murmur/lib/jido_murmur/telemetry/req_llm_tracer.ex` — when a message has `:tool_calls`, call `flatten_tool_calls/2` with the message index and merge attributes. Ensure arguments are JSON-encoded via `Jason.encode!/1`

**Checkpoint**: Tool call details visible in traces — agents' reasoning loop is inspectable

---

## Phase 7: User Story 4 — Group Traces by Session (Priority: P3)

**Goal**: All traces from the same workspace share a `session.id` attribute for filtering

**Independent Test**: Conduct two conversations in different workspaces, filter by session in Phoenix, verify isolation

### Tests for User Story 4

- [x] T026 [US4] Write test for session enrichment in `apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs` — set process metadata with agent_id, populate `JidoMurmur.ObsTracer.Cache` with `{agent_id, workspace_id, display_name}`, fire `:start` event, verify span has `"session.id" => workspace_id`

### Implementation for User Story 4

- [x] T027 [US4] Update `handle_event([:req_llm, :request, :start], ...)` in `apps/jido_murmur/lib/jido_murmur/telemetry/req_llm_tracer.ex` — read agent_id from current process metadata (via `Logger.metadata()[:agent_id]` or `Process.get(:jido_agent_id)`), look up `JidoMurmur.ObsTracer.Cache.lookup(agent_id)` to get `{workspace_id, display_name}`, add `"session.id" => workspace_id` to span attributes. Store `%{workspace_id: workspace_id, display_name: display_name}` as `agent_context` in ETS alongside span_ctx
- [x] T028 [US4] Write test for session enrichment on cross-process stop in `apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs` — verify that session.id set at start time survives the cross-process stop (already on span from start event)

**Checkpoint**: Traces are filterable by session/workspace

---

## Phase 8: User Story 5 — Identify Agent Identity (Priority: P3)

**Goal**: Each trace shows which agent (e.g., "Bob", "Alice") initiated the LLM call

**Independent Test**: Send messages to two different agents, verify each trace shows the correct agent name

### Tests for User Story 5

- [x] T029 [US5] Write test for agent name enrichment in `apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs` — same cache setup as T026, verify span has `"llm.agent_name" => display_name` attribute

### Implementation for User Story 5

- [x] T030 [US5] Add `"llm.agent_name" => display_name` to start attributes in `apps/jido_murmur/lib/jido_murmur/telemetry/req_llm_tracer.ex` alongside the session.id enrichment from T027 — the cache lookup already provides `display_name`, just add the attribute
- [x] T031 [US5] Write test for missing agent context (graceful degradation) in `apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs` — fire `:start` event without process metadata set, verify span is created without `session.id` or `llm.agent_name` but is otherwise complete (no crash)

**Checkpoint**: Agent identity visible on traces — multi-agent debugging enabled

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Final validation, cleanup, and hardening

- [x] T032 [P] Run `mix compile --warnings-as-errors` for `apps/jido_murmur` and fix any warnings in `apps/jido_murmur/lib/jido_murmur/telemetry/req_llm_tracer.ex`
- [x] T033 [P] Run `mix credo --strict` and fix any issues in `apps/jido_murmur/lib/jido_murmur/telemetry/req_llm_tracer.ex`
- [x] T034 Run full test suite `mix test apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs` — all tests must pass
- [x] T035 Run `mix precommit` to validate complete project health
- [x] T036 Run quickstart.md validation — start Phoenix, send agent message, verify in Arize Phoenix UI that traces show input messages, output messages, token counts, tool calls, session ID, and agent name

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 config — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Phase 2 helpers — MVP target
- **US6 (Phase 4)**: Depends on Phase 2 and Phase 3 (uses same start/stop handlers)
- **US2 (Phase 5)**: Depends on Phase 2 — largely already implemented, audit only
- **US3 (Phase 6)**: Depends on Phase 2 helpers (flatten_tool_calls)
- **US4 (Phase 7)**: Depends on Phase 2 ETS expansion (T009)
- **US5 (Phase 8)**: Depends on Phase 7 (uses same cache lookup from T027)
- **Polish (Phase 9)**: Depends on all story phases being complete

### User Story Dependencies

- **US1 (P1) + US6 (P1)**: Core pair — must be done first. US6 validates US1 works for streaming
- **US2 (P2)**: Independent — can run in parallel with US1 after Phase 2
- **US3 (P2)**: Independent — can run in parallel with US1 after Phase 2
- **US4 (P3)**: Independent — can run in parallel after Phase 2
- **US5 (P3)**: Depends on US4 (shares the cache lookup implementation in T027)

### Within Each User Story

- Tests written FIRST, verified to fail before implementation
- Helper functions before handler integration
- Start handler before stop handler
- Core path before edge cases

### Parallel Opportunities

- T001 and T002 (config changes) can run in parallel
- T004, T005, T006, T007, T008 (all foundational helpers) touch the same file but independent functions — parallelizable if working on separate sections
- T010, T011, T012, T013 (foundational tests) can run in parallel
- After Phase 2: US2 (T021-T022) and US3 (T023-T025) can run in parallel with US1
- After Phase 2: US4 (T026-T028) can run in parallel with US1-US3
- T032 and T033 (lint/compile) can run in parallel

---

## Parallel Example: After Phase 2

```
# These can all proceed simultaneously after Phase 2 completes:

Track A (MVP):    US1 (T014→T017) → US6 (T018→T020)
Track B (tokens): US2 (T021→T022)
Track C (tools):  US3 (T023→T025)
Track D (session): US4 (T026→T028) → US5 (T029→T031)
```

---

## Implementation Strategy

### MVP First (User Story 1 + 6)

1. Complete Phase 1: Setup (config changes)
2. Complete Phase 2: Foundational (helpers + tests)
3. Complete Phase 3: US1 — Conversation content in traces
4. Complete Phase 4: US6 — Streaming reliability
5. **STOP and VALIDATE**: Run quickstart.md — traces show messages in Phoenix
6. Deploy/demo if ready — this is the core feature

### Incremental Delivery

1. Setup + Foundational → Helpers ready
2. US1 + US6 → Message content visible, streaming works (MVP!)
3. US2 → Token counts verified (likely already working)
4. US3 → Tool calls visible
5. US4 + US5 → Session grouping + agent identity
6. Polish → Clean compilation, full test suite green, precommit passes

---

## Notes

- All changes touch only 2 source files: `req_llm_tracer.ex` and `req_llm_tracer_test.exs`, plus 2 config files
- No new dependencies, no new modules, no database changes
- US2 (tokens) is likely already working — T021 is an audit task
- Helpers (T004-T008) are private functions in the same module — they can be developed as one logical unit
- ETS schema change (T009) must be coordinated with existing tests (may need test updates)
