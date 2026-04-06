# ADR-008: Core-Owned Visible Ingress Messages

**Status**: Proposed
**Date**: 2026-04-06
**Ticket**: `specs/tickets/019-core-owned-visible-ingress-messages/`

## Context

Ticket 017 established a core-owned conversation projector for assistant-step messages and a Murmur-owned update contract for canonical conversation state.

That work also made a remaining ownership seam more obvious: visible user ingress is still created through two different paths.

- direct human messages sent from `WorkspaceLive` are still rendered optimistically by constructing `DisplayMessage.user(...)` in the LiveView before the message enters Murmur's canonical ingress path
- visible programmatic ingress already flows through `JidoMurmur.Ingress.ProgrammaticDelivery`, which delivers canonical input and emits a Murmur-owned `murmur.message.received` signal for the UI

Those paths are similar in product intent but different in ownership and behavior.

This leaves Murmur with split responsibility for visible top-level user messages:

- core owns canonical programmatic visible ingress
- the demo UI still mints canonical-looking direct human messages locally

That split has several downsides:

- the UI still knows too much about canonical message construction
- direct and programmatic ingress can drift in metadata, ids, ordering attachment, or future behavior
- future host UIs must rediscover where optimism ends and canonical conversation state begins
- reconnect and duplication behavior remain harder to reason about because some visible messages originate outside the canonical core boundary

The architectural direction established by ADR-001, ADR-003, ADR-005, and ADR-007 is that Murmur should own canonical runtime and display boundaries while UIs stay presentation- and orchestration-focused.

## Decision

Murmur should own canonical visible ingress message creation for all user-visible ingress, including direct human messages and programmatic messages.

Specifically:

- direct human sends must stop minting canonical `DisplayMessage` structs in `WorkspaceLive`
- direct human ingress and visible programmatic ingress must share one core-owned visible ingress contract
- the canonical visible user message should be emitted by core after ingress acceptance, using Murmur-owned identity and first-seen metadata
- UIs may still show transient local pending state for responsiveness, but that pending state is presentation-only and must not become the canonical conversation record
- reconciliation between transient pending UI state and the canonical visible message must also be owned by an explicit contract rather than by implicit append heuristics
- the direct-send path should align with the existing `murmur.message.received` model unless implementation experience reveals a clearer Murmur-owned replacement contract
- host applications should consume the same visible ingress contract regardless of whether the source was human or programmatic

## Consequences

Benefits:

- Murmur has one ownership boundary for visible top-level user messages
- direct and programmatic ingress metadata stay aligned by construction
- host UIs can treat visible ingress consistently instead of mixing local message creation with core-fed updates
- future ordering, actor metadata, trace metadata, and deduplication changes can happen inside core without LiveView-specific rewrites
- the conversation model becomes easier to explain: UIs render canonical messages from core and may optionally overlay transient pending state

Trade-offs:

- Murmur needs an explicit pending-to-canonical reconciliation story for responsive direct sends
- the UI will likely need a small pending-message abstraction instead of directly appending canonical display structs
- some existing tests that currently assert immediate local `DisplayMessage.user(...)` insertion will need to be rewritten around the new contract
- this tightens the expectation that core, not the UI, owns even more of the visible chat protocol