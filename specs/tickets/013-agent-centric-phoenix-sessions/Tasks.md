# Tasks: Agent-Centric Phoenix Sessions

## Task List

Format: `- [ ] T001 [P] Description with file path`
- **T001, T002, …** — sequential task ID
- **[P]** — present only when the task can run in parallel with others
- Include the exact file path to create or modify in the description

### P1 — Agent Sessions And Per-Loop Traces

- [ ] T001 Modify `apps/jido_murmur/lib/jido_murmur/runner.ex` and `apps/jido_murmur/lib/jido_murmur/observability/store.ex` so Phoenix `session.id` exports the executing agent session id, `murmur.request_id` remains the per-loop trace identifier, and active-run follow-up input stays inside the existing root trace.
- [ ] T002 Remove `interaction_id` from the canonical ingress and runtime metadata contracts in `apps/jido_murmur/lib/jido_murmur/ingress/input.ex`, `apps/jido_murmur/lib/jido_murmur/ingress/metadata.ex`, `apps/jido_murmur/lib/jido_murmur/ingress.ex`, `apps/jido_murmur/lib/jido_murmur/observability.ex`, and `apps/jido_murmur/lib/jido_murmur/signals/message_received.ex`.
- [ ] T003 Remove discussion-cache-based session rollover in `apps/jido_murmur/lib/jido_murmur/observability/conversation_cache.ex`, `apps/jido_murmur/lib/jido_murmur/table_owner.ex`, `apps/jido_murmur/lib/jido_murmur/agent_helper.ex`, and `apps/murmur_demo/lib/murmur_web/live/workspace_live.ex`.
- [ ] T004 Update delivery callers in `apps/jido_murmur/lib/jido_murmur/ingress/programmatic_delivery.ex` and `apps/jido_murmur/lib/jido_murmur/tell_action.ex` so they preserve only immediate parent-trace metadata and no longer pass or require `interaction_id`.
- [ ] T005 Update focused runtime tests in `apps/jido_murmur/test/jido_murmur/ingress/input_test.exs`, `apps/jido_murmur/test/jido_murmur/ingress/metadata_test.exs`, `apps/jido_murmur/test/jido_murmur/ingress/coordinator_test.exs`, `apps/jido_murmur/test/jido_murmur/runner_test.exs`, `apps/jido_murmur/test/jido_murmur/signals/message_received_test.exs`, and `apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs` for the simplified contract.

### P2 — Immediate Parent-Trace Causation

- [ ] T006 Preserve and verify immediate handoff causation in `apps/jido_murmur/lib/jido_murmur/tell_action.ex`, `apps/jido_murmur/lib/jido_murmur/runner.ex`, and related observability code so idle-started downstream work records `murmur.triggered_by_trace_id` without inventing a workflow or discussion id.
- [ ] T007 Add integration and demo coverage in `apps/jido_murmur/test/jido_murmur/integration/message_flow_test.exs`, `apps/jido_murmur/test/jido_murmur/integration/jido_interplay_test.exs`, `apps/murmur_demo/test/murmur/agents/inter_agent_test.exs`, `apps/murmur_demo/test/murmur/agents/runner_test.exs`, `apps/murmur_demo/test/murmur_web/live/workspace_live_test.exs`, and `apps/murmur_demo/test/murmur_web/live/workspace_live_integration_test.exs` for long-gap direct chat grouping, busy-run follow-up input, and idle downstream handoff causation.

### P3 — Docs And Validation

- [ ] T008 [P] Create `specs/decisions/ADR-006-agent-centric-phoenix-sessions-and-immediate-trace-causation.md` and update `specs/Architecture/observability.md` plus `specs/Architecture/jido-murmur.md` so the ground-truth docs describe agent-centric sessions, per-loop traces, and immediate parent-trace causation only.
- [ ] T009 [P] Update package-facing docs in `apps/jido_murmur/README.md` and any affected demo-owned observability examples so `interaction_id` no longer appears in the documented ingress or tracing model.
- [ ] T010 Run targeted suites touching `apps/jido_murmur/test/jido_murmur/integration/message_flow_test.exs` and `apps/murmur_demo/test/murmur/agents/inter_agent_test.exs`, then run `mix precommit` from `/Users/vincent.min/Projects/murmur`.

## Completion Criteria

All tasks checked off and acceptance criteria from Spec.md verified.