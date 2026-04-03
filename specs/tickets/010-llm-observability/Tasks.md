# Tasks: LLM Observability & Tracing

## Task List

Format: `- [ ] T001 [P] Description with file path`
- **T001, T002, …** — sequential task ID
- **[P]** — present only when the task can run in parallel with others
- Include the exact file path to create or modify in the description

Group tasks by user-story priority (P1 first). Each group should be an independently testable increment.

### P1 — Root Turn Traces And Payload Fidelity

- [ ] T000 Create `specs/tickets/010-llm-observability/data-contract.md` to define the OpenInference-aligned span attribute contract for agent, LLM, and tool spans, including Phoenix message-rendering requirements.
- [ ] T001 Modify `apps/jido_murmur/mix.exs`, `config/config.exs`, `config/runtime.exs`, and `config/test.exs` to remove AgentObs-specific wiring, declare Murmur-owned observability configuration, and keep explicit OpenTelemetry exporter settings.
- [ ] T002 Create `apps/jido_murmur/lib/jido_murmur/observability.ex`, `apps/jido_murmur/lib/jido_murmur/observability/tracer.ex`, and `apps/jido_murmur/lib/jido_murmur/observability/turn_context.ex` to own root turn lifecycle, active context propagation, and OpenInference-friendly attribute assembly.
- [ ] T003 Create `apps/jido_murmur/lib/jido_murmur/observability/stream_accumulator.ex` and modify `apps/jido_murmur/lib/jido_murmur/telemetry/req_llm_tracer.ex` to capture full streamed output text, preserve ordered `llm.input_messages.*` conversation attributes, and emit structured `llm.output_messages.*` assistant-message attributes.
- [ ] T004 Modify `apps/jido_murmur/lib/jido_murmur/runner.ex`, `apps/jido_murmur/lib/jido_murmur/observability/store.ex`, and `apps/jido_murmur/lib/jido_murmur/table_owner.ex` so each executed react loop starts and finishes exactly one root trace while Murmur attaches LLM and tool child spans using the merged `jido_ai` telemetry hooks.
- [ ] T005 [P] Update `apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs`, `apps/jido_murmur/test/jido_murmur/runner_test.exs`, and `apps/jido_murmur/test/jido_murmur/table_owner_test.exs` to verify root trace ownership, child-span attachment from Jido.AI telemetry, exact streamed output capture, ordered input conversation attributes, and structured assistant output messages.

### P1 — Steering Injection And Idle-Start Semantics

- [ ] T006 Modify `apps/jido_murmur/lib/jido_murmur/pending_queue.ex` to store structured message envelopes instead of raw message strings, including sender, steering, trace, and interaction metadata.
- [ ] T007 Modify `apps/jido_murmur/lib/jido_murmur/message_injector.ex` and `apps/jido_murmur/lib/jido_murmur/runner.ex` so messages injected while an agent is already running remain inside the active turn trace rather than creating a second root trace.
- [ ] T008 Modify `apps/jido_murmur/lib/jido_murmur/tell_action.ex` and `apps/jido_murmur/lib/jido_murmur/signals/message_received.ex` so idle-started inter-agent work creates a new root trace while preserving originating trace and interaction metadata.
- [ ] T009 [P] Update `apps/jido_murmur/test/jido_murmur/pending_queue_test.exs`, `apps/jido_murmur/test/jido_murmur/tell_action_test.exs`, and `apps/jido_murmur/test/jido_murmur/integration/message_flow_test.exs` to verify busy injection vs idle-start behavior.

### P1 — Per-Agent Conversation Sessions

- [ ] T010 Modify `apps/jido_murmur/lib/jido_murmur/agent_helper.ex`, `apps/jido_murmur/lib/jido_murmur/observability/tracer.ex`, and `apps/jido_murmur/lib/jido_murmur/telemetry/req_llm_tracer.ex` to use the stable agent conversation identity as `session.id` while continuing to attach agent, workspace, and team metadata.
- [ ] T011 [P] Update `apps/jido_murmur/test/jido_murmur/agent_helper_test.exs`, `apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs`, and `apps/jido_murmur/test/jido_murmur/integration/jido_interplay_test.exs` to verify multiple turn traces group under one long-lived agent session.

### P2 — Cross-Agent Workflow Correlation

- [ ] T012 Create `apps/jido_murmur/lib/jido_murmur/observability/interaction.ex` and modify `apps/jido_murmur/lib/jido_murmur/runner.ex`, `apps/jido_murmur/lib/jido_murmur/tell_action.ex`, and `apps/jido_murmur/lib/jido_murmur/message_injector.ex` to propagate a dedicated `interaction_id` alongside workspace and team correlation metadata.
- [ ] T013 [P] Update `apps/jido_murmur/test/jido_murmur/integration/message_flow_test.exs`, `apps/jido_murmur/test/jido_murmur/integration/jido_interplay_test.exs`, and `apps/jido_murmur/test/jido_murmur/tell_action_test.exs` to verify multi-agent fan-out remains filterable and causally linked without collapsing trace boundaries.

### P1 — Phoenix Message Rendering Contract

- [ ] T014 Modify `apps/jido_murmur/lib/jido_murmur/observability/store.ex`, `apps/jido_murmur/lib/jido_murmur/telemetry/req_llm_tracer.ex`, and a new Jido.AI telemetry bridge under `apps/jido_murmur/lib/jido_murmur/telemetry/` so Phoenix renders message-oriented input and output views for LLM spans instead of only plain text fields.
- [ ] T015 [P] Update `apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs`, `apps/jido_murmur/test/jido_murmur/integration/jido_interplay_test.exs`, and focused telemetry tests to verify system, user, assistant, assistant-tool-call, and tool-role messages survive end to end in the exported LLM and tool span attributes.

### P1 — Telemetry Integration Refresh

- [ ] T016 Modify `apps/murmur_demo/lib/murmur/application.ex` and create a Jido.AI telemetry bridge in `apps/jido_murmur/lib/jido_murmur/telemetry/` that attaches to the merged `[:jido, :ai, :request|llm|tool, ...]` lifecycle events at startup.
- [ ] T017 Update `apps/jido_murmur/lib/jido_murmur/streaming_plugin.ex` and related integration tests so Murmur receives `ai.tool.started` alongside the existing runtime signals.

## Completion Criteria

All tasks checked off and acceptance criteria from Spec.md verified.