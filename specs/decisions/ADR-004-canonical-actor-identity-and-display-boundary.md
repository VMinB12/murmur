# ADR-004: Canonical Actor Identity And Display Boundary

**Status**: Accepted
**Date**: 2026-04-05
**Ticket**: `specs/tickets/015-actor-identity-and-display-projection-cleanup/`

## Context

Ticket 014 cleaned up the runtime metadata boundary and removed fallback behavior from the ingress-adjacent runtime slice. That work made a second boundary stand out more clearly: Murmur still overloads `sender_name` across at least three different concerns.

- In runtime tool context, `sender_name` currently means the current agent's identity.
- In canonical ingress metadata and visible inbound messages, `sender_name` means the upstream sender of the current message.
- In UI-facing projection, `sender_name` is also used as a display label and is sometimes inferred from message content itself.

The current code compensates for that ambiguity in a few ways:

- `JidoMurmur.Ingress.Metadata.tool_context/3` writes both `sender_name` and `origin_sender_name` to distinguish meanings.
- `JidoMurmur.MessageInjector` still reads `runtime_context[:sender_name]`, which is actually the current agent name rather than the origin sender.
- `JidoMurmur.UITurn` still falls back across atom and string keys and infers sender identity from a `"[Name]:"` content prefix when metadata is absent.

These adaptations work, but they keep identity semantics implicit and force presentation code to repair runtime ambiguities after the fact.

## Decision

Murmur should introduce one explicit actor-identity boundary and one explicit display-message boundary.

Specifically:

- Runtime context should stop overloading `sender_name` and instead expose explicit identity fields such as `current_actor`, `origin_actor`, or equivalent clearly named values.
- Human, agent, and system-originated messages should share one canonical actor representation rather than passing free-form display names through multiple layers.
- UI projection should consume one canonical display-message shape and must not infer sender identity from message content or mixed atom/string payload access.
- Message text formatting such as `"[Alice]: ..."` may remain a presentation choice, but it must no longer be the fallback source of truth for actor identity.

The exact module names and struct names are left to the implementation ticket, but the system should converge on explicit identity semantics rather than continuing to encode them in overloaded maps and string prefixes.

## Consequences

Benefits:

- runtime and UI layers will use the same actor semantics instead of translating between partial conventions
- `MessageInjector`, observability, tell delivery, and UI rendering become easier to reason about because field names describe one meaning each
- sender-label inconsistencies such as `"You"` versus `"You (human)"` can be handled intentionally at the presentation edge
- `UITurn` can stop carrying compatibility parsing logic that exists only because display data is not yet canonicalized

Trade-offs:

- another focused cleanup ticket is required across runtime context, thread projection, and UI rendering
- existing tests that assert on `sender_name` semantics will need to be updated to the clearer identity contract
- a small amount of new explicit data modeling is required, likely in the form of one or two lightweight structs