# Journal: Canonical Conversation Step Ordering

## 2026-04-06

- Resumed implementation after the first ordering slices landed and validated.
- Detected spec drift: request-level assistant projection cannot represent the desired steering behavior for multi-iteration ReAct runs because one outer request can contain several assistant/tool phases.
- Decided to broaden ticket 017 from request-level message ordering to top-level assistant-step ordering.
- Decided to fold the required `UITurn` retirement work into ticket 017 so the canonical read boundary can land in one pass without a transitional adapter.
- Archived ticket 018 as superseded by the broadened scope of ticket 017.
- Shipped the assistant-step rewrite: canonical top-level messages now sort by Murmur-owned first-seen metadata, one outer request may yield multiple assistant-step messages, and persisted/live projection share the same read-model boundary.
- Removed `UITurn` from the canonical read path, introduced `DisplayMessage.ToolCall`, updated the architecture docs, and validated the result with focused regressions plus `mix precommit`.
- Retained optimistic local human message creation at the LiveView edge; the ticket closes with assistant-step ordering and visible programmatic ingress ordering owned canonically by Murmur.