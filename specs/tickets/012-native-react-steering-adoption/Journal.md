# Journal: Native ReAct Steering Adoption

## 2026-04-04

- Resumed the ticket after clarifying that the preferred long-term model is not a Murmur mailbox.
- Reframed the architecture around a single ingress coordinator actor per agent session.
- Updated the recommendation to prefer a jido_ai-aligned ingress contract built on `content`, `source`, `refs`, and optional `expected_request_id`.
- Confirmed that request transformers should remain only for Murmur-owned context shaping, not busy-run message delivery.
- Defined `Tasks.md` around the coordinator actor, jido_ai-aligned ingress input, runtime refactor, and legacy queue removal.