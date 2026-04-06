# Spec: Data Model And Contract Architecture

## User Stories

### US-1: Canonical domain concepts in one place (Priority: P1)

**As a** Murmur maintainer, **I want** a dedicated architecture document for the canonical domain model, **so that** core entities, identity rules, relationships, state transitions, and invariants are not redefined differently across tickets and implementation passes.

**Independent test**: Read `specs/Architecture/data-model.md` and verify it captures Murmur's major canonical entities and read models, including their identities, relationships, and key lifecycle or invariant rules.

### US-2: Canonical boundary contracts in one place (Priority: P1)

**As a** Murmur maintainer or host-app integrator, **I want** a dedicated architecture document for cross-boundary data contracts, **so that** producers and consumers can align on canonical shapes without relying on implementation archaeology.

**Independent test**: Read `specs/Architecture/data-contracts.md` and verify it documents key contracts with owner, producer, consumer, canonical shape, transport or persistence representation, and compatibility notes.

### US-3: Navigable architecture without duplication (Priority: P2)

**As a** future contributor, **I want** the architecture index and related docs to link to the new data-model and data-contract documents, **so that** the architecture remains navigable and the new docs complement rather than duplicate the rest of the spec set.

**Independent test**: Inspect `specs/Architecture/README.md` and related architecture docs and verify the new files are linked and cross-referenced without leaving conflicting definitions behind.

## Acceptance Criteria

- [ ] `specs/Architecture/data-model.md` exists and documents Murmur's canonical domain concepts.
- [ ] The data-model document distinguishes canonical domain entities from derived or read models.
- [ ] The data-model document captures identity rules, relationships, and lifecycle or invariant rules for the concepts that materially affect Murmur's architecture.
- [ ] `specs/Architecture/data-contracts.md` exists and documents Murmur's key cross-boundary contracts.
- [ ] The data-contracts document includes, for each important contract, the owner, producer, consumer, canonical shape, and transport or persistence representation.
- [ ] The data-contracts document explicitly distinguishes canonical in-memory shapes from transport or persistence formats where they differ.
- [ ] `specs/Architecture/README.md` links to both new documents.
- [ ] Relevant existing architecture docs are updated or cross-referenced as needed so the new documents do not leave contradictory definitions behind.
- [ ] The new documents focus on stable architectural concepts and contracts rather than becoming exhaustive field-by-field dumps of the implementation.
- [ ] The new documents are consistent with the current architecture and with recent tickets and ADRs covering actor identity, conversation projection, and data-contract enforcement.

## Scope

### In Scope

- Creating `specs/Architecture/data-model.md`
- Creating `specs/Architecture/data-contracts.md`
- Updating `specs/Architecture/README.md` to link to the new documents
- Updating relevant architecture sub-documents where light cross-references or clarification are needed
- Clarifying canonical shape versus transport or persistence representation where that distinction matters architecturally

### Out of Scope

- Changing implementation code
- Rewriting the entire architecture section
- Creating exhaustive field-by-field schema inventories for every struct, signal, or database table
- Introducing new architectural behavior beyond the documentation needed to describe the current system clearly