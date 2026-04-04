# Plan: Frontend Architecture Review — murmur_web & murmur_demo

## Approach

1. Re-establish the package boundary around `jido_murmur_web` so it exposes a generic multi-agent workspace shell and generic artifact extension points, not built-in knowledge of SQL or arXiv workflows.
2. Move domain-specific artifact rendering and follow-up actions into `murmur_demo` or the responsible package-owned integration layer, and have `WorkspaceLive` delegate through that boundary instead of calling plugin code directly.
3. Refactor the workspace presentation into smaller, purpose-specific UI modules so split view, unified view, artifact navigation, and supporting controls can evolve without keeping all rendering logic inside one LiveView template.
4. Improve visual consistency with DaisyUI as the primary design system, especially for chat bubbles, collapsible detail blocks, tabbed artifact navigation, cards, and empty or loading states, while preserving the separate chat panel and artifact panel model.
5. Keep the current token streaming approach based on regular assigns and incremental string updates. This ticket is focused on frontend boundaries and presentation, not a rewrite of the streaming transport model.
6. Update tests, install surfaces, and architecture documentation alongside the refactor so the new package responsibilities are explicit and protected.

## Key Design Decisions

- `jido_murmur_web` remains a stateless reusable UI package. Host applications own business rules, plugin-specific schemas, and artifact-specific follow-up behaviors.
- Artifact rendering becomes explicitly registered by the consuming application instead of arriving through generic-library defaults for specific domains.
- Artifact follow-up actions, such as re-running a SQL query, are delegated through demo-owned integration modules rather than hardcoded package references inside the generic workspace flow.
- Workspace UI composition is split into smaller components in `murmur_demo`, but the core product model remains the same: split chat, unified chat, and a separate artifact panel.
- DaisyUI remains the primary UI vocabulary. The goal is to use it more coherently, not to migrate to a different component system.
- Breaking frontend changes are acceptable in this ticket if they remove coupling and produce a cleaner long-term package boundary.
- This plan changes package responsibilities and should be captured in an ADR plus architecture doc updates during implementation.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Boundary cleanup breaks current package consumers or installer output | Medium | High | Update component tests, install-task tests, and package docs in the same change set |
| Refactoring `WorkspaceLive` and its template regresses split or unified workflows | Medium | High | Preserve test IDs, expand LiveView regression coverage, and keep changes staged around extracted UI modules |
| Removing built-in artifact defaults makes the demo experience harder to wire | Low | Medium | Provide a demo-owned registry and integration modules that act as the reference implementation |
| DaisyUI-driven UI refactor introduces churn without improving clarity | Medium | Medium | Limit design changes to interaction consistency and component clarity, while preserving the validated layout model |
| Artifact action abstractions become too broad for current needs | Medium | Medium | Introduce the narrowest integration boundary that supports existing SQL and arXiv workflows plus a safe fallback path |
