# Spec: Remove Raw AI Stream Chat Path

## User Stories

### US-1: Demo chat subscribes only to canonical chat contracts (Priority: P1)

**As a** Murmur maintainer, **I want** the demo chat surface to subscribe only to Murmur-owned canonical chat signals, **so that** the runtime rendering contract is obvious and the UI no longer carries dead stream-handling code.

**Independent test**: The demo chat surface still renders direct human messages, streamed assistant updates, and completion or failure state correctly without subscribing to the raw stream topic.

### US-2: Dead raw-stream fanout is removed when unused (Priority: P1)

**As a** Murmur maintainer, **I want** unused raw `ai.*` PubSub fanout removed when there is no runtime consumer, **so that** the app avoids needless event traffic and contract confusion.

**Independent test**: If no runtime consumer remains, removing the raw stream topic and broadcast path does not change canonical chat behavior in focused tests.

### US-3: Internal canonical reduction remains unchanged (Priority: P2)

**As a** Murmur maintainer, **I want** raw `ai.*` lifecycle facts to remain available as internal projector inputs, **so that** this cleanup does not accidentally change canonical assistant-step reduction.

**Independent test**: Existing projector and conversation-read-model tests still pass after the raw chat path is removed.

## Acceptance Criteria

- [ ] The demo chat surface no longer subscribes to the raw agent stream topic for conversation rendering.
- [ ] Dead `ai.*` chat handlers and related compatibility assumptions are removed from the demo chat surface.
- [ ] If no current runtime consumer remains, the extra raw-stream PubSub topic and broadcast path are removed.
- [ ] Canonical chat behavior continues to rely on Murmur-owned visible-ingress, conversation-update, completion, and failure contracts.
- [ ] Internal canonical reduction from raw `ai.*` lifecycle facts remains unchanged.

## Scope

### In Scope

- demo chat subscription cleanup
- removal of dead `ai.*` chat handlers
- raw-stream topic and broadcast cleanup if there is no remaining runtime consumer
- focused regression coverage for unchanged canonical chat behavior

### Out of Scope

- changing `ConversationReadModel` signal-reduction rules
- changing observability semantics beyond any direct dependency on the removed chat path
- changing artifact or task PubSub contracts