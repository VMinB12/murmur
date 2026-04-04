# Tasks: LLM Observability & Tracing

## Task List

Format: `- [ ] T001 [P] Description with file path`
- **T001, T002, …** — sequential task ID
- **[P]** — present only when the task can run in parallel with others
- Include the exact file path to create or modify in the description

Group tasks by user-story priority (P1 first). Each group should be an independently testable increment.

### P1 — Root Turn Traces And Payload Fidelity

- [x] T000 Create `specs/tickets/010-llm-observability/data-contract.md` to define the OpenInference-aligned span attribute contract for agent, LLM, and tool spans, including Phoenix message-rendering requirements.
- [x] T001 Modify `apps/jido_murmur/mix.exs`, `config/config.exs`, `config/runtime.exs`, and `config/test.exs` to remove AgentObs-specific wiring, declare Murmur-owned observability configuration, and keep explicit OpenTelemetry exporter settings.
- [x] T002 Create `apps/jido_murmur/lib/jido_murmur/observability.ex` and modify `apps/jido_murmur/lib/jido_murmur/observability/tracer.ex` plus `apps/jido_murmur/lib/jido_murmur/observability/store.ex` to own root turn lifecycle, active context propagation, and OpenInference-friendly attribute assembly.
- [x] T003 Modify `apps/jido_murmur/lib/jido_murmur/telemetry/req_llm_tracer.ex`, `apps/jido_murmur/lib/jido_murmur/telemetry/jido_ai_tracer.ex`, and `apps/jido_murmur/lib/jido_murmur/observability/store.ex` to capture full streamed output text, preserve ordered `llm.input_messages.*` conversation attributes, and emit structured `llm.output_messages.*` assistant-message attributes.
- [x] T004 Modify `apps/jido_murmur/lib/jido_murmur/runner.ex`, `apps/jido_murmur/lib/jido_murmur/observability/store.ex`, and `apps/jido_murmur/lib/jido_murmur/table_owner.ex` so each executed react loop starts and finishes exactly one root trace while Murmur attaches LLM and tool child spans using the merged `jido_ai` telemetry hooks.
- [x] T005 [P] Update `apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs`, `apps/jido_murmur/test/jido_murmur/runner_test.exs`, and `apps/jido_murmur/test/jido_murmur/table_owner_test.exs` to verify root trace ownership, child-span attachment from Jido.AI telemetry, exact streamed output capture, ordered input conversation attributes, and structured assistant output messages.

### P1 — Steering Injection And Idle-Start Semantics

- [x] T006 Modify `apps/jido_murmur/lib/jido_murmur/pending_queue.ex` to store structured message envelopes instead of raw message strings, including sender, steering, trace, and interaction metadata.
- [x] T007 Modify `apps/jido_murmur/lib/jido_murmur/message_injector.ex` and `apps/jido_murmur/lib/jido_murmur/runner.ex` so messages injected while an agent is already running remain inside the active turn trace rather than creating a second root trace.
- [x] T008 Modify `apps/jido_murmur/lib/jido_murmur/tell_action.ex` and `apps/jido_murmur/lib/jido_murmur/signals/message_received.ex` so idle-started inter-agent work creates a new root trace while preserving originating trace and interaction metadata.
- [x] T009 [P] Update `apps/jido_murmur/test/jido_murmur/pending_queue_test.exs`, `apps/jido_murmur/test/jido_murmur/tell_action_test.exs`, and `apps/jido_murmur/test/jido_murmur/integration/message_flow_test.exs` to verify busy injection vs idle-start behavior.

### P1 — Discussion Session Grouping

- [x] T010 Modify `apps/jido_murmur/lib/jido_murmur/agent_helper.ex`, `apps/jido_murmur/lib/jido_murmur/runner.ex`, `apps/jido_murmur/lib/jido_murmur/table_owner.ex`, and `apps/jido_murmur/lib/jido_murmur/observability/conversation_cache.ex` so direct chat uses a discussion-scoped `session.id` with inactivity rollover while continuing to attach agent, workspace, and team metadata.
- [x] T011 [P] Update `apps/jido_murmur/test/jido_murmur/agent_helper_test.exs`, `apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs`, `apps/jido_murmur/test/jido_murmur/integration/jido_interplay_test.exs`, and `apps/jido_murmur/test/jido_murmur/integration/message_flow_test.exs` to verify same-discussion reuse, timeout rollover, and explicit propagated interaction-id grouping.

### P2 — Cross-Agent Workflow Correlation

- [x] T012 Modify `apps/jido_murmur/lib/jido_murmur/runner.ex`, `apps/jido_murmur/lib/jido_murmur/tell_action.ex`, `apps/jido_murmur/lib/jido_murmur/message_injector.ex`, and `apps/jido_murmur/lib/jido_murmur/observability.ex` to propagate a dedicated `interaction_id` alongside workspace and team correlation metadata.
- [x] T013 [P] Update `apps/jido_murmur/test/jido_murmur/integration/message_flow_test.exs`, `apps/jido_murmur/test/jido_murmur/integration/jido_interplay_test.exs`, and `apps/jido_murmur/test/jido_murmur/tell_action_test.exs` to verify multi-agent fan-out remains filterable and causally linked without collapsing trace boundaries.

### P1 — Phoenix Message Rendering Contract

- [x] T014 Modify `apps/jido_murmur/lib/jido_murmur/observability/store.ex`, `apps/jido_murmur/lib/jido_murmur/telemetry/req_llm_tracer.ex`, and a new Jido.AI telemetry bridge under `apps/jido_murmur/lib/jido_murmur/telemetry/` so Phoenix renders message-oriented input and output views for LLM spans instead of only plain text fields.
- [x] T015 [P] Update `apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs`, `apps/jido_murmur/test/jido_murmur/integration/jido_interplay_test.exs`, and focused telemetry tests to verify system, user, assistant, assistant-tool-call, and tool-role messages survive end to end in the exported LLM and tool span attributes.

### P1 — Telemetry Integration Refresh

- [x] T016 Modify `apps/murmur_demo/lib/murmur/application.ex` and create a Jido.AI telemetry bridge in `apps/jido_murmur/lib/jido_murmur/telemetry/` that attaches to the merged `[:jido, :ai, :request|llm|tool, ...]` lifecycle events at startup.
- [x] T017 Update `apps/jido_murmur/lib/jido_murmur/streaming_plugin.ex` and related integration tests so Murmur receives `ai.tool.started` alongside the existing runtime signals.

## Completion Criteria

All tasks checked off and acceptance criteria from Spec.md verified.