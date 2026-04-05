# Journal: Agent-Centric Phoenix Sessions

## 2026-04-05

- Resumed the ticket after clarifying that Murmur should not model Phoenix sessions around inferred discussions.
- Reframed the target observability model around one Phoenix session per agent and one root trace per executed react loop.
- Rejected `interaction_id` and proposed lineage-style replacements as canonical metadata for this ticket because one react loop may absorb several upstream messages.
- Chose the minimal causation model: keep only immediate parent-trace metadata through `sender_trace_id` and `murmur.triggered_by_trace_id`.
- Updated the ticket spec, created an ADR, and wrote Plan.md plus Tasks.md around the simplified model.
- Implemented the runtime refactor by removing `interaction_id`, deleting `ConversationCache`, exporting Phoenix `session.id` from the agent session id, and keeping only immediate parent-trace causation in ingress, runner, and observability code.
- Updated focused runtime and demo tests for the simplified contract, added integration coverage for long-gap direct delivery and idle parent-trace handoff behavior, and validated the umbrella with `mix precommit`.