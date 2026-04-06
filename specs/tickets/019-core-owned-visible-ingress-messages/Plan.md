# Plan: Core-Owned Visible Ingress Messages

## Approach

Extend Murmur's ingress boundary so direct human sends emit the same kind of core-owned visible message contract that visible programmatic ingress already uses.

The target end state is:

- `WorkspaceLive` sends input through `JidoMurmur.Ingress` and no longer mints canonical direct human messages
- core emits the canonical visible top-level user message after ingress acceptance
- the UI optionally overlays a transient pending-send state keyed by a local temporary id or request token until the canonical message arrives
- canonical visible user messages carry Murmur-owned identity, actor metadata, and first-seen ordering metadata regardless of source

Where practical, the direct path should reuse the same underlying helper or event shape already used by `JidoMurmur.Ingress.ProgrammaticDelivery` rather than introducing a second nearly identical path.

## Key Design Decisions

### 1. Treat optimism as presentation, not canonical state

Do not keep the current model where the UI creates a canonical-looking `DisplayMessage.user(...)` and hopes core later lines up with it.

Instead, let the UI maintain a small pending-send overlay whose only job is responsiveness.

### 2. Prefer one visible ingress signal contract

If the existing `murmur.message.received` contract can serve both direct and programmatic visible ingress cleanly, reuse it.

If not, introduce one clearer Murmur-owned replacement contract and migrate both paths to it together.

### 3. Keep routing and orchestration in the UI, but message creation in core

The LiveView should still decide which session a direct send targets. Once the target session and input are determined, the canonical visible message should come back from core.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Pending-state reconciliation creates duplicate user messages | Medium | High | Use an explicit reconciliation key or predictable canonical echo path and cover it with LiveView tests |
| Direct-send UX feels slower after removing local canonical append | Medium | Medium | Keep a lightweight pending overlay so the composer still feels immediate |
| Direct and programmatic ingress contracts diverge again in follow-up changes | Medium | High | Route both through one shared helper or one shared signal contract in core |