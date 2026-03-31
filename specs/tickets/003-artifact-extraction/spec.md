# Feature Specification: Artifact System Extraction

**Feature Branch**: `003-artifact-extraction`  
**Created**: 2026-03-29  
**Status**: Draft  
**Input**: Redesign artifact API (merge callback, metadata, ctx, scope) and extract into jido_artifacts package. Derived from architecture analysis report Sections 1 and 5.

## User Scenarios & Testing

### User Story 1 - Tool Author Emits Artifacts with Custom Merge (Priority: P1)

A developer building a domain tool package (e.g., arxiv search, code analysis) uses `Artifact.emit/4` to surface structured results to the frontend. They control how new data combines with existing data via a `merge` callback — appending search results, replacing a displayed item, or applying custom deduplication logic.

**Why this priority**: The merge callback is the core API primitive. Every tool author interacts with it. Getting this right determines whether the extracted package is useful or frustrating.

**Independent Test**: Can be tested by calling `Artifact.emit/4` with various merge options (no merge = replace, append helper, bounded append, custom function) and verifying the resulting signal data contains the correctly merged result.

**Acceptance Scenarios**:

1. **Given** an agent with no existing "papers" artifact, **When** a tool calls `Artifact.emit(ctx, "papers", [paper1], merge: &Artifact.Merge.append/2)`, **Then** the emitted signal data contains a `merge_result` of `[paper1]`
2. **Given** an agent with existing "papers" artifact containing `[paper1, paper2]`, **When** a tool calls `Artifact.emit(ctx, "papers", [paper3], merge: &Artifact.Merge.append/2)`, **Then** the signal's `merge_result` is `[paper1, paper2, paper3]`
3. **Given** an agent with existing "papers" artifact containing 60 items, **When** a tool calls `Artifact.emit(ctx, "papers", [new_paper], merge: &Artifact.Merge.append_max(50))`, **Then** the signal's `merge_result` contains exactly 50 items (the most recent 50)
4. **Given** any existing artifact state, **When** a tool calls `Artifact.emit(ctx, "displayed_paper", paper)` with no merge option, **Then** the signal data contains the new paper as a direct replacement (no `merge_result` key)
5. **Given** an existing artifact, **When** a tool calls `Artifact.emit(ctx, "papers", nil, merge: fn _, _ -> nil end)`, **Then** the signal's `merge_result` is `nil`, causing the artifact to be deleted on store

---

### User Story 2 - StoreArtifact Persists with Metadata Envelope (Priority: P1)

When the artifact plugin intercepts an artifact signal and overrides to `StoreArtifact`, the action wraps the data in a metadata envelope containing `updated_at`, `source`, and `version` fields, then stores it in `agent.state.artifacts`.

**Why this priority**: The metadata envelope is essential for debugging (when was this updated?), multi-agent tracing (who produced this?), and change detection (has this changed since last render?). It must ship with v1.

**Independent Test**: Can be tested by running `StoreArtifact` with mock agent state and verifying the output contains the metadata envelope structure.

**Acceptance Scenarios**:

1. **Given** an agent with no existing artifacts, **When** `StoreArtifact` runs with `%{artifact_name: "papers", artifact_data: [paper1]}`, **Then** `agent.state.artifacts["papers"]` equals `%{data: [paper1], updated_at: <timestamp>, source: <agent_id>, version: 1}`
2. **Given** an agent with existing "papers" artifact at version 2, **When** `StoreArtifact` runs with new data, **Then** the version increments to 3 and `updated_at` reflects the current time
3. **Given** a signal with `merge_result: nil`, **When** `StoreArtifact` runs, **Then** the artifact key is removed from `agent.state.artifacts`
4. **Given** a signal with `merge_result: [merged_data]`, **When** `StoreArtifact` runs, **Then** the stored `data` field contains `[merged_data]` (the pre-merged result, not the raw signal data)

---

### User Story 3 - Artifact Signals Carry CloudEvents Identity (Priority: P2)

When `emit/4` creates an artifact signal, it populates the CloudEvents `source` and `subject` fields from the action context, enabling signal tracing and filtering by entity.

**Why this priority**: CloudEvents compliance enables interoperability with external systems and audit trails, but the system functions without it (signals still route correctly without source/subject).

**Independent Test**: Can be tested by calling `emit/4` with a context that contains agent identity and verifying the resulting signal struct has `source` and `subject` fields populated.

**Acceptance Scenarios**:

1. **Given** an action context with `ctx[:state][:__agent_id__]` set to `"agent_abc"`, **When** `emit(ctx, "papers", data)` is called, **Then** the signal has `source: "/jido_artifacts/papers"` and `subject: "/agents/agent_abc"`
2. **Given** an action context without agent identity, **When** `emit(ctx, "papers", data)` is called, **Then** the signal has `source: "/jido_artifacts/papers"` and `subject: nil` (degrades gracefully)

---

### User Story 4 - Extract jido_artifacts as Independent Package (Priority: P1)

The three artifact modules (`Artifact`, `ArtifactPlugin`, `StoreArtifact`) plus the new `Artifact.Merge` helpers are extracted into a standalone `jido_artifacts` package. Domain tool packages (e.g., jido_arxiv) depend on `jido_artifacts` instead of `jido_murmur`, eliminating the heavyweight transitive dependency.

**Why this priority**: This is the structural goal of the entire feature. Without extraction, every future tool package pulls in the full orchestration layer. The extraction must happen before any packages are published to Hex.

**Independent Test**: Can be tested by verifying that jido_arxiv compiles and its tests pass with only `jido_artifacts` (not `jido_murmur`) as a dependency for artifact functionality.

**Acceptance Scenarios**:

1. **Given** the extracted `jido_artifacts` package, **When** jido_arxiv's `mix.exs` lists `{:jido_artifacts, path: "../jido_artifacts"}` and removes any direct artifact dependency on jido_murmur, **Then** jido_arxiv compiles and all artifact-related tests pass
2. **Given** the extracted package, **When** `JidoArtifacts.Artifact.emit/4` is called from any tool action, **Then** it produces valid `%Directive.Emit{}` structs identical in behavior to the pre-extraction version
3. **Given** jido_murmur's `mix.exs` lists `{:jido_artifacts, path: "../jido_artifacts"}`, **When** the full umbrella test suite runs, **Then** all 416+ tests pass with zero failures
4. **Given** the extracted package, **When** `config :jido_artifacts, pubsub: MyApp.PubSub` is set, **Then** `ArtifactPlugin` broadcasts on the configured PubSub module

---

### User Story 5 - Scope Field Reserves Cross-Agent Artifact Support (Priority: P3)

The `emit/4` API accepts an optional `:scope` option (`:agent` default, `:workspace` reserved). For now, only `:agent` is implemented. `:workspace` is reserved in the signal contract for future cross-agent artifact sharing.

**Why this priority**: Forward-compatible design that costs almost nothing to implement now but saves a breaking API change later. Not urgent since workspace-scoped artifacts aren't needed yet.

**Independent Test**: Can be tested by verifying that `scope: :agent` flows through the signal data and that `scope: :workspace` either raises a clear error or is silently accepted.

**Acceptance Scenarios**:

1. **Given** a call to `Artifact.emit(ctx, "papers", data, scope: :agent)`, **When** the signal is created, **Then** the signal data includes `scope: :agent`
2. **Given** a call to `Artifact.emit(ctx, "papers", data, scope: :workspace)`, **When** the signal reaches `ArtifactPlugin`, **Then** the plugin either logs a warning and ignores or returns an error indicating workspace scope is not yet implemented
3. **Given** a call to `Artifact.emit(ctx, "papers", data)` with no scope option, **When** the signal is created, **Then** the scope defaults to `:agent`

---

### User Story 6 - Renderer Unwraps Metadata Envelope (Priority: P2)

The `ArtifactPanel` dispatcher in jido_murmur_web unwraps the metadata envelope before passing data to renderers. Renderers continue to receive `assigns.data` as raw artifact data, unaware of the envelope.

**Why this priority**: Without this, all existing renderers break when the metadata envelope is introduced. It's a small change but critical for backward compatibility.

**Independent Test**: Can be tested by rendering an artifact panel component with an artifact stored in the new envelope format and verifying the renderer receives only the `data` field.

**Acceptance Scenarios**:

1. **Given** an artifact stored as `%{data: [paper1, paper2], updated_at: ..., version: 2}`, **When** the `ArtifactPanel` renders, **Then** the renderer component receives `[paper1, paper2]` as its data assign — not the full envelope
2. **Given** an artifact stored in the old format (raw data, no envelope) during migration, **When** the `ArtifactPanel` renders, **Then** it gracefully handles the missing envelope and passes data through directly

---

### Edge Cases

- What happens when `merge` receives `nil` as existing data (first emit for a new artifact)? The merge function receives `nil` as the first argument. Built-in helpers like `append/2` must handle this via `existing || []` or similar guard.
- What happens when the action context has no `:state` key? `emit/4` degrades gracefully: `source` is set from the artifact name, `subject` is nil. No crash.
- What happens when a tool passes both `merge:` and data is a non-list value to `Artifact.Merge.append/2`? `List.wrap/1` normalizes the input, so single values become `[value]`.
- What happens when `StoreArtifact` receives a signal without `merge_result` or `artifact_data`? Default behavior is replace. If both are missing, the artifact is set to `nil` (effectively deleted).

## Requirements

### Functional Requirements

- **FR-001**: `Artifact.emit/4` MUST accept an optional `:merge` keyword option that takes a function `(existing, new) -> merged`
- **FR-002**: When `:merge` is provided, `emit/4` MUST apply the merge eagerly using current artifact state from context, and include the result as `merge_result` in the signal data
- **FR-003**: When no `:merge` is provided, `emit/4` MUST produce a signal that causes `StoreArtifact` to replace the existing artifact data entirely
- **FR-004**: `StoreArtifact` MUST wrap stored data in a metadata envelope: `%{data: term(), updated_at: DateTime.t(), source: String.t(), version: integer()}`
- **FR-005**: `StoreArtifact` MUST increment the version counter on each update to the same artifact name
- **FR-006**: `StoreArtifact` MUST delete the artifact entry when the merged result is `nil`
- **FR-007**: `emit/4` MUST populate the signal's `source` field with `"/jido_artifacts/#{name}"`
- **FR-008**: `emit/4` MUST populate the signal's `subject` field from the action context's agent identity, if available
- **FR-009**: The `Artifact.Merge` module MUST provide built-in helpers: `append/2`, `prepend/2`, `append_max/1`, `prepend_max/1`, `upsert_by/1`
- **FR-010**: `emit/4` MUST accept an optional `:scope` keyword (`:agent` default, `:workspace` reserved)
- **FR-011**: The extracted `jido_artifacts` package MUST depend only on `jido`, `jido_signal`, `jido_action`, and `phoenix_pubsub` — not on `jido_murmur`
- **FR-012**: `ArtifactPlugin` MUST broadcast artifact updates via a configurable PubSub module (read from `:jido_artifacts` application config)
- **FR-013**: The `ArtifactPanel` renderer dispatcher MUST unwrap the metadata envelope, passing only `artifact.data` to renderer components
- **FR-014**: The `ArtifactPanel` MUST handle artifacts stored in the old format (no envelope) gracefully during migration

### Key Entities

- **Artifact**: A named unit of structured data produced by tool actions and displayed in the UI. Identified by name (string), scoped to an agent or workspace.
- **Artifact Envelope**: The storage wrapper around artifact data: `%{data: term(), updated_at: DateTime.t(), source: String.t(), version: integer()}`
- **Merge Function**: A `fn(existing, new) -> merged` callback that determines how new artifact data combines with existing state. Applied eagerly at emit time.
- **Artifact Signal**: A `Jido.Signal` with type `"artifact.#{name}"`, carrying artifact data through the plugin system.
- **ArtifactPlugin**: A Jido Plugin that intercepts `artifact.*` signals, broadcasts via PubSub, and overrides to `StoreArtifact`.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Tool authors can emit artifacts with any custom merge strategy using a single `:merge` option — no framework changes needed for new merge behaviors
- **SC-002**: Every stored artifact includes `updated_at`, `source`, and `version` metadata accessible for debugging and tracing
- **SC-003**: Domain tool packages (e.g., jido_arxiv) compile and pass tests depending only on `jido_artifacts`, eliminating the transitive dependency on `jido_murmur`
- **SC-004**: The full umbrella test suite passes with zero regressions after extraction
- **SC-005**: The `jido_artifacts` package has fewer than 5 direct dependencies
- **SC-006**: All existing UI renderers continue to work without modification after the metadata envelope is introduced
- **SC-007**: Artifact signals include CloudEvents `source` and `subject` fields, enabling signal filtering and audit trails

## Assumptions

- The Jido action context (`ctx`) provides access to agent state via `ctx[:state]`, including artifact data at `ctx[:state][:artifacts]`. This is required for eager merge in `emit/4`. If the path differs, the implementation must adapt to the actual Jido context structure.
- The `__agent_id__` field is available in agent state. If not, the agent module can set it during `on_before_cmd` or it can be threaded via `runtime_context`.
- No packages have been published to Hex yet, so the extraction involves zero breaking changes for external consumers.
- The Phoenix PubSub module is available and configured in the consuming application.
- The Jido checkpoint/hibernate system persists `agent.state.artifacts` generically — no storage-layer changes are needed in jido_murmur for the metadata envelope.
- The renderer dispatch in `ArtifactPanel` is a single point where data is passed to renderers, making the envelope unwrap a one-line change.
