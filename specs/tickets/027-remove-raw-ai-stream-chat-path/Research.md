# Research: Remove Raw AI Stream Chat Path

## Objective

Define a small cleanup that removes the dead raw `ai.*` chat-rendering path without changing Murmur's canonical conversation update model.

## Findings

### The demo chat surface no longer renders from raw `ai.*` signals

- `WorkspaceLive` now ignores `ai.*` signals and renders from `murmur.message.received`, `murmur.conversation.updated`, and completion or failure signals.
- The current product chat contract already says host UIs should render canonical Murmur-owned messages rather than raw lifecycle facts.

### The app still subscribes to and broadcasts the raw stream topic

- `AgentHelper.subscribe/1` still subscribes the demo app to the raw agent stream topic.
- `StreamingPlugin` still broadcasts raw `ai.*` lifecycle signals over that topic after applying them to the canonical projector.
- In current app code, there is no remaining chat-rendering consumer that uses those PubSub messages.

### Internal reduction still needs raw lifecycle facts

- `ConversationReadModel` still needs raw `ai.*` lifecycle facts as internal input for building canonical assistant-step state.
- That does not mean the UI needs those signals as a public rendering protocol.

## Options Considered

| Option | Pros | Cons |
|--------|------|------|
| Leave the raw stream topic in place as harmless compatibility baggage | No refactor cost | Keeps dead event traffic and preserves an unnecessary mental model in the chat surface |
| Remove only the demo subscription and ignore handler | Smallest code change | Leaves unused broadcast fanout and topic ownership behind |
| Remove the dead chat path end-to-end, and keep the raw topic only if a real runtime consumer still needs it | Simplifies the product chat contract and removes unused event traffic | Requires confirming there is no remaining runtime consumer beyond tests or future assumptions |

## Recommendation

Choose the third option.

Remove the raw `ai.*` chat path from the demo surface and then remove the extra PubSub broadcast and topic if no current runtime consumer still needs it.

Murmur should continue to reduce raw lifecycle facts internally, but the chat UI should subscribe only to Murmur-owned canonical chat contracts.

## References

- `apps/murmur_demo/lib/murmur_web/live/workspace_live.ex`
- `apps/jido_murmur/lib/jido_murmur/agent_helper.ex`
- `apps/jido_murmur/lib/jido_murmur/streaming_plugin.ex`
- `apps/jido_murmur/lib/jido_murmur/conversation_read_model.ex`
- `apps/jido_murmur/lib/jido_murmur/topics.ex`
- `specs/Architecture/conversation-read-model.md`
- `specs/Architecture/data-contracts.md`