# Tasks: Runtime Metadata Boundary Cleanup

## Task List

Format: `- [ ] T001 [P] Description with file path`
- **T001, T002, …** — sequential task ID
- **[P]** — present only when the task can run in parallel with others
- Include the exact file path to create or modify in the description

### P1 — Canonical Metadata Projection

- [ ] T001 Create the explicit runtime metadata projection boundary in `apps/jido_murmur/lib/jido_murmur/ingress/metadata.ex` and cover canonical metadata accessors plus tool-context projection in `apps/jido_murmur/test/jido_murmur/ingress/metadata_test.exs`.
- [ ] T002 Extend canonical ingress metadata validation and builders in `apps/jido_murmur/lib/jido_murmur/ingress/input.ex` to support `hop_count` and related runtime metadata rules, and update `apps/jido_murmur/test/jido_murmur/ingress/input_test.exs` accordingly.
- [ ] T003 Introduce configurable hop-limit policy in `apps/jido_murmur/lib/jido_murmur/config.ex` and any tell-related runtime modules, then cover default and override behavior in `apps/jido_murmur/test/jido_murmur/tell_action_test.exs` or equivalent focused tests.
- [ ] T004 Change tell hop-limit exhaustion handling in `apps/jido_murmur/lib/jido_murmur/tell_action.ex` so the calling agent receives an informative tool-visible outcome rather than a crash-shaped failure, and cover that behavior in `apps/jido_murmur/test/jido_murmur/tell_action_test.exs`.
- [ ] T005 Refactor runtime context assembly in `apps/jido_murmur/lib/jido_murmur/runner.ex` to project tool-visible context from canonical ingress metadata, removing duplicated ref lookup, ad hoc context shaping, and fallback metadata readers in this path.
- [ ] T006 Fix inter-agent hop-depth propagation in `apps/jido_murmur/lib/jido_murmur/tell_action.ex` and add chained tell coverage in `apps/jido_murmur/test/jido_murmur/tell_action_test.exs` and `apps/murmur_demo/test/murmur/agents/inter_agent_test.exs`.
- [ ] T007 Align ingress-adjacent runtime data structures in `apps/jido_murmur/lib/jido_murmur/ingress/input.ex`, `apps/jido_murmur/lib/jido_murmur/ingress/metadata.ex`, and `apps/jido_murmur/lib/jido_murmur/runner.ex` so one concept has one primary structure, without retaining legacy compatibility branches for unpublished package consumers.

### P2 — Shared Programmatic Delivery Path

- [ ] T008 Create the shared visible programmatic delivery helper in `apps/jido_murmur/lib/jido_murmur/ingress.ex` and `apps/jido_murmur/lib/jido_murmur/ingress/programmatic_delivery.ex`, then cover it in `apps/jido_murmur/test/jido_murmur/ingress/coordinator_test.exs` or equivalent focused ingress tests.
- [ ] T009 Migrate task-assignment delivery in `apps/jido_tasks/lib/jido_tasks/tools/add_task.ex` and `apps/murmur_demo/lib/murmur_web/live/workspace_live.ex` to the shared helper, removing duplicated inbound-message signal, canonical input assembly, and any fallback metadata assembly in those paths.
- [ ] T010 Update programmatic delivery coverage in `apps/jido_tasks/test/jido_tasks/tools/add_task_test.exs`, `apps/murmur_demo/test/murmur_web/live/workspace_live_test.exs`, and `apps/murmur_demo/test/murmur/agents/runner_test.exs` so shared helper behavior and metadata consistency are locked in.

### P3 — Docs And Validation

- [ ] T011 [P] Update architecture documentation in `specs/Architecture/jido-murmur.md` to describe canonical ingress metadata as the source of truth for downstream runtime metadata, the configurable hop-limit policy, the informative tell-limit outcome, the aligned runtime structures around that boundary, and the shared programmatic delivery path.
- [ ] T012 [P] Revalidate ingress and inter-agent behavior in `apps/jido_murmur/test/jido_murmur/integration/message_flow_test.exs` and any other affected integration suites, then run `mix test` and `mix precommit` from `/Users/vincent.min/Projects/murmur`.

## Completion Criteria

All acceptance criteria from `Spec.md` are satisfied, hop-depth propagation is verified across chained inter-agent tells, the hop-limit policy is configurable with a documented default, tell-limit exhaustion produces an informative agent-visible outcome without crashing the run, duplicated producer-side metadata assembly has been replaced by one explicit projection boundary plus one shared visible programmatic delivery path, and the affected runtime slice no longer carries legacy paths or fallback behavior.