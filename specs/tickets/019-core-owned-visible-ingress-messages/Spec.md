# Spec: Core-Owned Visible Ingress Messages

## User Stories

### US-1: One canonical visible ingress path (Priority: P1)

**As a** Murmur maintainer, **I want** direct human sends and visible programmatic sends to produce canonical top-level user messages through the same core-owned contract, **so that** visible ingress ownership is not split between LiveView and core.

**Independent test**: Send one direct human message and one visible programmatic message, inspect the resulting canonical messages, and verify both were created through the Murmur-owned ingress contract rather than by `WorkspaceLive` constructing canonical `DisplayMessage.user(...)` structs locally.

### US-2: Responsive sends without UI-owned canonical state (Priority: P1)

**As a** workspace user, **I want** direct sends to still feel immediate, **so that** moving canonical message creation into core does not make the UI feel laggy.

**Independent test**: Send a direct message from the workspace UI and verify the screen shows immediate pending feedback that later reconciles cleanly with the canonical message from core without duplication.

### US-3: Reconnect-safe visible user message identity (Priority: P2)

**As a** Murmur maintainer, **I want** visible user-message identity and first-seen metadata to come from one Murmur-owned source, **so that** refresh, reconnect, and cross-host rendering do not depend on LiveView-local message ids or append order.

**Independent test**: Send a direct human message, reconnect or remount the UI, and verify the reloaded canonical conversation contains the same visible user message identity and ordering metadata without a separate UI-owned fallback.

## Acceptance Criteria

- [ ] `apps/murmur_demo/lib/murmur_web/live/workspace_live.ex` no longer constructs canonical direct human messages with `JidoMurmur.DisplayMessage.user(...)` before calling `JidoMurmur.Ingress`.
- [ ] Direct human ingress and visible programmatic ingress share one Murmur-owned visible message contract.
- [ ] Canonical visible direct human messages receive Murmur-owned identity and first-seen metadata in core rather than in the LiveView.
- [ ] The workspace UI may keep transient pending-send state, but that state is explicitly presentation-only and is not stored as a canonical conversation message.
- [ ] Pending direct-send UI state reconciles with the canonical message from core without producing duplicates.
- [ ] Split and unified chat views continue to show direct human messages immediately enough for normal interactive use.
- [ ] The canonical direct-send path preserves actor metadata consistency with visible programmatic ingress.
- [ ] Regression tests cover direct send, unified mention routing, and reconnect/remount behavior after the ownership change.
- [ ] Architecture documentation reflects that visible ingress ownership is now fully core-owned if the contract description changes.

## Scope

### In Scope

- Moving canonical direct human-message creation into `jido_murmur`
- Aligning direct and programmatic visible ingress contracts
- Introducing or refining transient pending UI state for direct sends
- Updating LiveView tests and any core ingress tests affected by the ownership change
- Updating architecture docs if the visible ingress contract changes materially

### Out of Scope

- Redesigning chat composer UX beyond what is needed for pending-state reconciliation
- Changing assistant-step segmentation or conversation ordering rules
- Reworking artifact or task-board update boundaries