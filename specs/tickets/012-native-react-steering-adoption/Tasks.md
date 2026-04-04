# Tasks: Native ReAct Steering Adoption

## Task List

Format: `- [ ] T001 [P] Description with file path`
- **T001, T002, …** — sequential task ID
- **[P]** — present only when the task can run in parallel with others
- Include the exact file path to create or modify in the description

### P1 — Coordinator-Owned Delivery Protocol

- [ ] T001 Create the architectural decision record in `specs/decisions/ADR-002-single-ingress-coordinator-actor.md` and align the session-runtime description in `specs/Architecture/jido-murmur.md` to the coordinator-owned delivery model.
- [ ] T002 Create the canonical jido_ai-aligned ingress input contract in `apps/jido_murmur/lib/jido_murmur/ingress/input.ex` and cover normalization plus metadata-shape rules in `apps/jido_murmur/test/jido_murmur/ingress/input_test.exs`.
- [ ] T003 Create the coordinator public API in `apps/jido_murmur/lib/jido_murmur/ingress.ex` and the per-session coordinator GenServer in `apps/jido_murmur/lib/jido_murmur/ingress/coordinator.ex`.
- [ ] T004 Add coordinator supervision, naming, and lifecycle wiring in `apps/jido_murmur/lib/jido_murmur/supervisor.ex` and `apps/jido_murmur/lib/jido_murmur/agent_helper.ex`.
- [ ] T005 Extend the LLM adapter boundary with native control calls in `apps/jido_murmur/lib/jido_murmur/llm.ex`, `apps/jido_murmur/lib/jido_murmur/llm/real.ex`, and `apps/jido_murmur/lib/jido_murmur/llm/mock.ex`.
- [ ] T006 Refactor direct-run execution in `apps/jido_murmur/lib/jido_murmur/runner.ex` so the coordinator owns ask-versus-steer routing and Runner only performs run execution plus await handling.
- [ ] T007 Update caller entry points in `apps/murmur_demo/lib/murmur_web/live/workspace_live.ex`, `apps/jido_murmur/lib/jido_murmur/tell_action.ex`, and `apps/jido_tasks/lib/jido_tasks/tools/add_task.ex` to build canonical ingress input and deliver through `JidoMurmur.Ingress`.
- [ ] T008 Refactor request shaping in `apps/jido_murmur/lib/jido_murmur/message_injector.ex` and `apps/jido_sql/lib/jido_sql/request_transformer.ex` so transformers enrich context only and no longer deliver busy-run follow-up input.
- [ ] T009 Update correlation and observability handling for `refs`-based ingress metadata in `apps/jido_murmur/lib/jido_murmur/observability.ex`, `apps/jido_murmur/lib/jido_murmur/observability/store.ex`, and `apps/jido_murmur/lib/jido_murmur/observability/conversation_cache.ex`.
- [ ] T010 Add coordinator and contract tests in `apps/jido_murmur/test/jido_murmur/ingress/coordinator_test.exs`, `apps/jido_murmur/test/jido_murmur/ingress/input_test.exs`, and `apps/jido_murmur/test/jido_murmur/runner_test.exs`.
- [ ] T011 Add end-to-end runtime coverage in `apps/jido_murmur/test/jido_murmur/integration/message_flow_test.exs`, `apps/jido_murmur/test/jido_murmur/integration/jido_interplay_test.exs`, `apps/murmur_demo/test/murmur/agents/runner_test.exs`, and `apps/murmur_demo/test/murmur/agents/inter_agent_test.exs` for idle `ask`, busy `steer`, busy `inject`, race retries, and metadata propagation.

### P2 — Simplification And Documentation

- [ ] T012 Narrow or remove the legacy semantic queue implementation in `apps/jido_murmur/lib/jido_murmur/pending_queue.ex`, `apps/jido_murmur/lib/jido_murmur/table_owner.ex`, `apps/jido_murmur/test/jido_murmur/pending_queue_test.exs`, and `apps/murmur_demo/test/murmur/agents/pending_queue_test.exs`.
- [ ] T013 Replace legacy queue-delivery expectations in `apps/murmur_demo/test/murmur/agents/message_injector_test.exs`, `apps/murmur_demo/test/murmur/agents/edge_case_test.exs`, and `apps/murmur_demo/test/murmur/agents/reconnect_test.exs` with coordinator and context-shaping assertions.
- [ ] T014 [P] Update generated and package-facing examples in `apps/jido_murmur/lib/mix/tasks/jido_murmur.gen.profile.ex`, `apps/jido_murmur/README.md`, and `apps/jido_sql/README.md` to describe the coordinator and the jido_ai-aligned ingress contract.
- [ ] T015 [P] Update architecture and compatibility documentation in `specs/Architecture/README.md`, `specs/Architecture/jido-murmur.md`, `specs/Architecture/jido-sql.md`, `apps/murmur_demo/README.md`, `apps/jido_murmur/mix.exs`, and `apps/jido_sql/mix.exs`, then run `mix test` and `mix precommit` to verify the refactor.

## Completion Criteria

All tasks checked off and acceptance criteria from Spec.md verified.