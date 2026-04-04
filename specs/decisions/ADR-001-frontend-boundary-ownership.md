# ADR-001: Frontend Boundary Ownership

**Status**: Accepted
**Date**: 2026-04-04
**Ticket**: `specs/tickets/011-frontend-architecture-review/`

## Context

`jido_murmur_web` had grown beyond a generic workspace shell. The shared artifact panel shipped built-in arXiv renderers, and `murmur_demo` kept SQL-specific artifact follow-up behavior directly inside `WorkspaceLive`. That made the reusable package depend on product-specific assumptions and left the demo's main LiveView responsible for both orchestration and domain presentation.

Ticket 011 required a clearer separation between the reusable frontend library and the demo application while preserving Murmur's core interaction model: split and unified chat views plus a separate artifact panel.

## Decision

We established the following frontend ownership boundary:

- `jido_murmur_web` owns reusable chat and artifact-shell primitives only.
- `jido_murmur_web` no longer ships domain-specific artifact renderer defaults.
- Consuming applications provide explicit artifact renderer registries and own artifact-specific follow-up actions.
- `murmur_demo` owns SQL and arXiv presentation through `MurmurWeb.Artifacts.Registry`, `MurmurWeb.Components.Artifacts`, and `MurmurWeb.Artifacts.Actions`.
- `WorkspaceLive` delegates presentation to demo-owned workspace components and delegates state projection or persistence helpers to `MurmurWeb.Live.WorkspaceState`.

## Consequences

Positive:

- The shared package can compile and run without SQL- or arXiv-specific knowledge.
- Host applications can introduce new artifact types and follow-up behavior without changing `jido_murmur_web`.
- The demo app keeps the reference UX while making domain ownership explicit.
- Workspace presentation is easier to evolve because rendering, orchestration, and domain integration now have clearer module boundaries.

Trade-offs:

- Consumers must wire a renderer registry instead of relying on built-in defaults.
- More modules now participate in workspace rendering, so the boundary must stay documented.
- Some frontend APIs and template structure changed, and backward compatibility was intentionally not preserved for this refactor.