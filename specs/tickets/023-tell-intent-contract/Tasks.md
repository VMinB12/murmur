# Tasks: Tell Intent Contract

## P1: Advisory Tell Intent Contract

- [x] T001 Update `apps/jido_murmur/lib/jido_murmur/tell_action.ex` to add a required `intent` parameter validated as a closed enum with the approved intent set, and keep `run/2` fully asynchronous.
- [x] T002 Update `apps/jido_murmur/lib/jido_murmur/tell_action.ex` to embed the LLM-facing intent matrix from this ticket into the `tell` tool description in a maintainable form that stays aligned with the approved wording.
- [x] T003 Update `apps/jido_murmur/lib/jido_murmur/tell_action.ex` to replace the current sender-only tell formatting with one canonical HTML comment envelope that carries sender and intent ahead of the human-facing tell body in idle-start and busy-inject paths.
- [x] T004 Update `apps/jido_murmur_web/lib/jido_murmur_web/components/chat_message.ex` and any related message-rendering helpers so tell-generated messages render through the markdown renderer while direct human messages remain raw text.
- [x] T005 Update `apps/jido_murmur/test/jido_murmur/tell_action_test.exs` to cover required intent validation, valid and invalid enum values, unchanged hop-limit behavior, and canonical comment-envelope formatting.
- [x] T006 Update `apps/murmur_demo/test/murmur/agents/inter_agent_test.exs` and any other relevant inter-agent tests under `apps/murmur_demo/test/murmur/agents/` to verify tell comment-envelope formatting and unchanged asynchronous idle and busy delivery behavior.
- [x] T007 Update `apps/jido_murmur_web/test/jido_murmur_web/components/chat_test.exs` and any direct-message rendering tests to verify tell-only markdown rendering, hidden tell-envelope omission, and unchanged raw rendering for direct human messages.
- [x] T008 Update `apps/jido_murmur/README.md`, `specs/Architecture/jido-murmur.md`, and `specs/Architecture/data-contracts.md` to document the required `intent` enum, the HTML comment tell envelope, tell-only markdown rendering, and the fact that direct human messages remain raw text.
- [x] T009 Run focused tests for the touched tell, ingress, markdown-rendering, and inter-agent files, then run `mix precommit` from `/Users/vincent.min/Projects/murmur`.