# Research: Conversation Snapshot Source Boundary Cleanup

## Objective

Define a small, implementation-ready cleanup that removes ad hoc source discovery and thaw-driven offline history recovery from `ConversationProjector` without changing Murmur's canonical conversation model.

## Findings

### `ConversationProjector` currently mixes projection with source discovery

- `ConversationProjector` owns canonical reduction, which is the right responsibility.
- It also currently decides how to find conversation entries by checking for a live process, pulling state from the running agent, or thawing an offline agent to recover thread entries.
- That means reduction behavior and source-selection behavior are coupled inside one module.

### Offline conversation history currently goes through a broader runtime-restore path than the read side needs

- In the current snapshot path, offline history is recovered through `jido_mod().thaw(...)` and then unpacked from agent state.
- That is broader than the conversation read side requires because the snapshot path only needs replayable thread entries.
- The storage layer already owns direct thread persistence and reconstruction capability, so the conversation snapshot path should not need a full restored runtime just to read history.

### Not every thaw usage should move in this ticket

- Agent startup still legitimately uses thaw because it is restoring executable runtime state.
- Artifact loading may also still need thaw because artifacts currently live in agent state rather than in the conversation thread log.
- This ticket should therefore stay scoped to conversation snapshot loading and reconciliation only.

## Options Considered

| Option | Pros | Cons |
|--------|------|------|
| Leave source discovery inside `ConversationProjector` | No immediate refactor cost | Keeps reduction and source selection coupled, and keeps thaw in the conversation snapshot path |
| Move the helpers elsewhere but keep offline snapshot loading thaw-based | Smaller diff | Does not actually remove the leaky runtime-restore dependency from the conversation read path |
| Introduce a dedicated snapshot-source boundary and use direct thread history when offline | Cleans up projector ownership, narrows the offline read path, and preserves current behavior | Requires a small refactor plus focused regression coverage |

## Recommendation

Choose the third option.

Introduce a dedicated conversation snapshot-source boundary that answers one question: what canonical replayable entries are available for this session right now?

That boundary should:

- read from the live agent thread when the agent is running
- read from persisted thread history directly when the agent is offline
- return data in the same replay-ready shape the projector already expects

`ConversationProjector` should then consume that boundary instead of discovering sources itself.

## References

- `apps/jido_murmur/lib/jido_murmur/conversation_projector.ex`
- `apps/jido_murmur/lib/jido_murmur/conversation_read_model.ex`
- `apps/jido_murmur/lib/jido_murmur/storage/ecto.ex`
- `apps/jido_murmur/lib/jido_murmur/agent_helper.ex`
- `specs/tickets/024-conversation-snapshot-freshness-contract/`