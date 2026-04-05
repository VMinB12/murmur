# Journal: Native ReAct Steering Adoption

## 2026-04-04

- Resumed the ticket after clarifying that the preferred long-term model is not a Murmur mailbox.
- Reframed the architecture around a single ingress coordinator actor per agent session.
- Updated the recommendation to prefer a jido_ai-aligned ingress contract built on `content`, `source`, `refs`, and optional `expected_request_id`.
- Confirmed that request transformers should remain only for Murmur-owned context shaping, not busy-run message delivery.
- Defined `Tasks.md` around the coordinator actor, jido_ai-aligned ingress input, runtime refactor, and legacy queue removal.
- Started implementation with ADR-002, ingress coordinator modules, LLM adapter control calls, and Runner handoff to ingress.
- Removed the legacy runtime delivery module and ETS table, migrated production callers onto `JidoMurmur.Ingress`, and rewrote legacy delivery tests around active-run steer/inject semantics.
- Removed the final compatibility wrapper around direct runner delivery, aligned package and architecture docs with ingress-first delivery, marked the ticket complete, and revalidated the repo with `mix test` and `mix precommit`.

## 2026-04-05

- Performed a final cleanup pass after completion and removed the remaining ingress compatibility seam built around `from_legacy`.
- Narrowed the public ingress API to explicit direct human delivery plus canonical programmatic input delivery, then revalidated with focused tests and `mix precommit`.