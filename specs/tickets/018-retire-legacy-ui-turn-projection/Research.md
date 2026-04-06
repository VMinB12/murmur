# Research: Retire Legacy UITurn Projection

## Objective

Determine whether `UITurn` is still required after ticket 016, and identify the remaining dependencies that keep the canonical conversation read path tied to a legacy projection module.

## Findings

### The canonical read model still delegates persisted projection to `UITurn`

`ConversationReadModel.from_entries/2` still calls `UITurn.project_entries/1` for persisted thread-state projection. This means the new canonical read boundary still depends on a legacy module for one of its core entry points.

### Canonical conversation types still depend on `UITurn.ToolCall`

`ConversationReadModel.Turn` and `DisplayMessage` both still reference `UITurn.ToolCall`. That keeps a canonical type dependency anchored in a legacy namespace even though turn updates are now owned by `jido_murmur`.

### `UITurn` still carries presentation-oriented defaults

`UITurn` still handles actor wording defaults such as rendering a human actor with the label `"You"`. That behavior is compatible with current UI output, but it reinforces that the module grew out of rendering concerns rather than a core read-model ownership boundary.

## Options Considered

| Option | Pros | Cons |
|--------|------|------|
| Keep `UITurn` as a permanent adapter | Minimal short-term code churn | Leaves the canonical read model dependent on a legacy UI-oriented namespace and makes ownership less clear |
| Move only `ToolCall` but keep `UITurn.project_entries/1` | Reduces one obvious dependency | Still leaves persisted canonical projection outside the new read-model boundary |
| Retire `UITurn` and move all remaining projection ownership under `jido_murmur` canonical conversation modules | Makes ownership explicit, simplifies mental model, and aligns with ticket 016's architecture | Requires coordinated refactoring across projection code, tests, and docs |

## Recommendation

Retire `UITurn` and move the remaining projection and tool-call responsibilities into canonical conversation modules owned by `jido_murmur`.

The end state should be that persisted-entry projection, canonical turn assembly, and tool-call value types all live under the same read-model boundary that already owns live incremental updates.

## References

- `apps/jido_murmur/lib/jido_murmur/conversation_read_model.ex`
- `apps/jido_murmur/lib/jido_murmur/conversation_read_model/turn.ex`
- `apps/jido_murmur/lib/jido_murmur/display_message.ex`
- `apps/jido_murmur/lib/jido_murmur/ui_turn.ex`
- `specs/decisions/ADR-005-canonical-conversation-read-model.md`