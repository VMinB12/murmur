# Spec: Shared Session Contract Type

## User Stories

### US-1: Core modules share one Murmur-owned session contract (Priority: P1)

**As a** Murmur maintainer, **I want** ingress, runner, projector, and related helpers to reference one shared session contract module, **so that** session boundary rules do not drift across local `session_like` aliases.

**Independent test**: The touched core modules compile and run against shared `JidoMurmur.SessionContract` types instead of redefining local `session_like` maps.

### US-2: Layered session variants stay explicit (Priority: P1)

**As a** Murmur maintainer, **I want** the shared contract to distinguish between read-side identity requirements and full delivery-target requirements, **so that** each boundary asks for only the fields it actually needs.

**Independent test**: Read-side modules use the narrower identity contract while ingress and runner modules use the richer delivery-target contract.

### US-3: Dialyzer-safe open maps remain centralized (Priority: P2)

**As a** Murmur maintainer, **I want** support for richer runtime session maps captured in one shared contract definition, **so that** future type widening does not need to be repeated piecemeal.

**Independent test**: The shared contract allows extra runtime keys through one open-map definition and the focused test suite still passes.

## Acceptance Criteria

- [x] A Murmur-owned shared session contract module defines the stable session map variants used across the core package.
- [x] The duplicated local `session_like` type aliases in ingress, runner, projector, and visible-message modules are replaced with shared contract references.
- [x] The shared contract keeps open-map support for richer runtime session structs in one place.
- [x] Architecture documentation records the shared session contract as a stable internal boundary.

## Scope

### In Scope

- shared session type module creation
- migration of duplicated `session_like` aliases to shared types
- layered session variants for read-side versus delivery-target boundaries
- architecture documentation for the session contract

### Out of Scope

- changing the persisted `AgentSession` schema
- changing runtime session behavior beyond type ownership
- broad dialyzer cleanup unrelated to duplicated session map types