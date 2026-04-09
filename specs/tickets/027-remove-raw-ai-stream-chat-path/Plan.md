# Plan: Remove Raw AI Stream Chat Path

## Approach

Remove the raw `ai.*` chat path from the demo surface first, then remove the extra stream-topic fanout if no real runtime consumer remains.

The intended end state is:

- the demo chat surface subscribes only to Murmur-owned canonical chat contracts
- raw `ai.*` lifecycle facts remain internal projector inputs rather than part of the product chat protocol
- the extra PubSub stream topic survives only if a current runtime consumer still needs it

## Key Design Decisions

### 1. Canonical chat rendering should expose only Murmur-owned contracts

The chat surface should render:

- `murmur.message.received`
- `murmur.conversation.updated`
- completion and failure lifecycle signals

It should not subscribe to or reason about raw `ai.*` lifecycle messages.

### 2. Internal reduction is not the same thing as UI transport

`ConversationReadModel` can continue to reduce raw `ai.*` facts internally.

This ticket changes the UI-facing transport path, not the internal read-model inputs.

### 3. Remove fanout only after confirming there is no runtime consumer

If some current runtime code still depends on the raw stream topic, the ticket should narrow first to removing the demo-side chat coupling and then make the remaining dependency explicit.

## Data Model And Contract Impact

- No change to `DisplayMessage` or canonical conversation-update payloads.
- The demo UI stops depending on the raw `ai.*` PubSub path.
- The raw stream topic may be removed if it no longer serves a real runtime contract.

## Risks And Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| A hidden runtime consumer still depends on the raw stream topic | Medium | Medium | Inventory runtime consumers first and remove the broadcast only if none remain |
| The cleanup accidentally removes observability behavior instead of only chat behavior | Low | High | Keep internal signal recording separate from UI PubSub cleanup |
| Tests still encode older assumptions about the raw stream path | Medium | Medium | Update focused tests to assert canonical chat behavior rather than topic-level internals |