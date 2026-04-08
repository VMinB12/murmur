# Research: Shared Session Contract Type

## Objective

Define the follow-up work needed to replace duplicated `session_like` type declarations with one shared session contract that expresses Murmur's stable session boundary clearly and reduces future dialyzer drift.

## Findings

### `session_like` is duplicated across the core package

- The current codebase defines `@type session_like` in at least these modules:
  - `JidoMurmur.ConversationProjector`
  - `JidoMurmur.Ingress`
  - `JidoMurmur.Ingress.Input`
  - `JidoMurmur.Ingress.ProgrammaticDelivery`
  - `JidoMurmur.Ingress.VisibleMessage`
  - `JidoMurmur.Runner`
- These types largely describe the same concept: a session-shaped map carrying stable identifiers such as `id`, `workspace_id`, and `agent_profile_id`, with some call sites also requiring `display_name`.

### The duplicates already drift in small but meaningful ways

- Some modules require `display_name`; others do not.
- Recent dialyzer cleanup added `optional(atom()) => any()` in multiple places to widen acceptance for extra keys.
- Repeating these shape tweaks across many modules is a maintenance smell because the same boundary semantics are being updated by hand.

### This is a boundary-contract issue, not just a style issue

- Session shape is used across producer and consumer boundaries inside `jido_murmur`, not only within one implementation detail.
- The contract matters for ingress delivery, runner execution, projector reconciliation, and visible-message emission.
- That makes it a shared data-contract concern rather than a purely local type-alias preference.

### One shared type may still need layered variants

- Not every call site needs exactly the same fields.
- The likely shape is not one overly broad type, but a small hierarchy such as:
  - base session identity contract
  - session contract with display metadata
  - module-specific extensions only where justified
- That keeps the canonical boundary explicit while still allowing narrower or richer variants when needed.

## Options Considered

| Option | Pros | Cons |
|--------|------|------|
| Leave the duplicated `session_like` types in place | No refactor cost | Continued drift, repeated dialyzer churn, and weaker contract ownership |
| Replace every local type with one broad catch-all session map type | Fastest consolidation | Risks hiding which fields are actually required at each boundary |
| Introduce a shared session contract module with a small set of layered types | Centralizes ownership while preserving useful field distinctions | Requires coordinated updates across several modules |

## Recommendation

Choose the third option.

Create one Murmur-owned session contract module that defines the stable shared types and documents which fields are required for each boundary slice. Then migrate the duplicated `session_like` declarations to those shared types. This should reduce type drift, make dialyzer fixes local instead of repetitive, and clarify the session boundary in the architecture.

## Suggested Scope For The Follow-Up Ticket

- Inventory all duplicated `session_like` type declarations and group them by actual field requirements.
- Define a shared contract module for base session identity plus any justified richer variants.
- Migrate core modules to reference the shared type definitions.
- Add regression coverage or compile-time verification where helpful so future drift is caught early.
- Update architecture docs if the shared session contract becomes a documented long-lived boundary.

## References

- `apps/jido_murmur/lib/jido_murmur/conversation_projector.ex`
- `apps/jido_murmur/lib/jido_murmur/ingress.ex`
- `apps/jido_murmur/lib/jido_murmur/ingress/input.ex`
- `apps/jido_murmur/lib/jido_murmur/ingress/programmatic_delivery.ex`
- `apps/jido_murmur/lib/jido_murmur/ingress/visible_message.ex`
- `apps/jido_murmur/lib/jido_murmur/runner.ex`
- `specs/Architecture/data-contracts.md`