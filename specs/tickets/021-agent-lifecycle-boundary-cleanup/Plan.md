# Plan: Agent Lifecycle Boundary Cleanup

## Approach

Promote the lifecycle behavior that `murmur_demo` currently re-implements into a core-owned helper or small lifecycle module, then update `WorkspaceLive` to call that API instead of thawing, starting, and cleaning up agents itself.

The target end state is:

- `jido_murmur` owns the lifecycle policy for session start, stop, and storage cleanup
- `murmur_demo` keeps orchestration concerns such as PubSub subscription and UI state updates, but stops duplicating runtime rules
- future host apps can reuse the same lifecycle API without copying demo code

## Key Design Decisions

### 1. Consolidate policy, not necessarily every call site

The goal is not to hide every runtime operation behind one mega-function.

The goal is to move policy decisions such as thaw-versus-fresh-start and checkpoint/thread cleanup into core so callers invoke a small explicit API.

### 2. Keep orchestration at the UI edge

`WorkspaceLive` should still manage PubSub subscriptions, form state, and UX flow. It should stop deciding how Murmur starts or cleans up agent runtime state.

### 3. Preserve current demo behavior first

This ticket is a boundary cleanup. It should preserve current observable behavior for workspace flows unless a smaller long-term API requires a narrowly justified adjustment.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Lifecycle helper extraction changes demo behavior subtly | Medium | High | Add focused tests around mount, add/remove agent, and clear team flows before and after refactor |
| Core lifecycle API becomes too broad or UI-specific | Medium | Medium | Keep the new API small and framed in terms of session lifecycle policy, not LiveView events |
| Cleanup responsibility becomes split in a new way | Medium | Medium | Move both startup and storage cleanup rules together so callers do not compose partial policy |