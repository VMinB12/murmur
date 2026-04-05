# Journal: Conversation Read Model And Streaming Consistency

## 2026-04-05

- Opened this follow-up after observing that live tool-call rendering can be incomplete during streaming and then appear after completion or refresh.
- Confirmed the UI currently uses two separate paths: an ad hoc `:streaming` map for live state and a thread-backed `UITurn`/`DisplayMessage` projection path for completed or refreshed history.
- Identified a likely timing bug where `murmur.message.completed` can mark a session idle before later `ai.llm.response` or `ai.tool.result` signals are handled, causing valid live tool-call data to be ignored.
- Drafted a ticket and spec aimed at introducing one canonical conversation read model or shared reduction boundary instead of patching the race in isolation.
- Wrote `Plan.md` after spec confirmation, moving the ticket to `planned` with a strategy centered on a package-owned conversation reducer/read boundary, explicit lifecycle state, and ordering-tolerant reconciliation between live signals and finalized thread history.
- Wrote `Tasks.md` to break the work into core read-model creation, LiveView/helper integration, and race/regression validation, leaving the ticket in `planned` pending task validation.