# Plan: Shared Session Contract Type

## Approach

Create one Murmur-owned session contract module with a small layered type hierarchy and migrate the duplicated `session_like` aliases to those shared types.

The intended end state is:

- read-side boundaries use a narrow identity contract
- ingress and runner boundaries use a richer delivery-target contract
- open-map support for runtime session structs is defined once

## Key Design Decisions

### 1. Use layered variants instead of one broad catch-all type

The shared contract distinguishes between:

- session identity needed by read-side modules
- full delivery-target data needed by ingress and runner

This keeps required fields explicit at each boundary.

### 2. Keep the contract Murmur-owned and internal

The shared type module documents a stable internal boundary inside `jido_murmur`.

It does not replace the persisted `AgentSession` schema or create a new runtime entity.

### 3. Preserve open-map compatibility in one place

The shared types keep `optional(atom()) => any()` so richer runtime session values remain accepted without repeating Dialyzer-oriented widenings in multiple modules.

## Risks And Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| A shared type becomes too broad and hides required-field differences | Medium | Medium | Keep separate identity and delivery-target variants |
| Modules continue to drift because some aliases are missed | Low | Medium | Migrate every current `session_like` alias in the affected core modules |
| The shared contract is treated as a schema replacement | Low | Low | Document it as an internal boundary type only |