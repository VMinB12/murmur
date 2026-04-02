# Spec: Data Contract Enforcement

## User Stories

### US-1: Typed artifact envelope struct (Priority: P1)

**As a** Murmur developer, **I want** the artifact envelope to be a typed struct with enforced keys, **so that** any code that constructs an envelope with missing fields fails immediately at construction time rather than silently producing bad data.

**Independent test**: Create an `%Envelope{}` with a missing required key → compilation or runtime error at the call site.

### US-2: Unified artifact data path (Priority: P1)

**As a** Murmur developer, **I want** the live update path and the persistence path to produce the same `%Envelope{}` struct for artifact data, **so that** renderers always receive one shape and don't need `unwrap_envelope` fallbacks.

**Independent test**: Emit an artifact signal, verify the data stored in `socket.assigns.artifacts` is an `%Envelope{}`. Hibernate and thaw the agent from a fresh checkpoint written after the 009 rollout, verify the data is the same `%Envelope{}` struct.

### US-3: Integration tests for artifact rendering (Priority: P1)

**As a** Murmur developer, **I want** integration tests that exercise the actual data flow from `StoreArtifact` through to artifact renderers, **so that** shape mismatches between producers and consumers are caught in CI before reaching production.

**Independent test**: Run `mix test` targeting the artifact rendering integration test module — all tests pass.

### US-4: Typed SQL result struct (Priority: P2)

**As a** `jido_sql` consumer, **I want** `QueryExecutor` to return a typed struct instead of a plain map, **so that** downstream code (renderers, formatters) can rely on a guaranteed shape.

**Independent test**: Call `QueryExecutor.execute/3` and pattern-match the return on `%QueryResult{columns: _, rows: _, total_rows: _}` — match succeeds.

### US-5: Manual Dialyzer support (Priority: P2)

**As a** Murmur developer, **I want** Dialyzer to remain an explicit manual check rather than part of the default precommit alias, **so that** we can use typespecs and static analysis without blocking the local commit flow.

**Independent test**: Run `mix precommit` — it does not invoke Dialyzer. Run `mix dialyzer` manually — it exits cleanly on a clean build.

### US-6: Typespecs on inter-module public APIs (Priority: P2)

**As a** Murmur developer, **I want** `@spec` annotations on all public functions at inter-module boundaries, **so that** Dialyzer can validate data flowing between packages.

**Independent test**: Run `mix dialyzer` — no warnings related to the annotated boundaries.

### US-7: Signal data typing (Priority: P3)

**As a** Murmur developer, **I want** signal schemas to define typed data fields instead of `:any`, **so that** signal emission and consumption have a documented contract at the application level without depending on changes to Jido itself.

**Independent test**: Inspect the relevant signal modules and verify they use concrete field types rather than `:any`. Consumers can pattern-match on the documented payload shape without defensive fallback clauses.

## Acceptance Criteria

### Envelope & data path (P1)

- [ ] `JidoArtifacts.Envelope` struct exists with `@enforce_keys [:data, :version, :source, :updated_at]`
- [ ] `JidoArtifacts.Envelope` has a `@type t` typespec
- [ ] `%Envelope{}` is the single canonical artifact shape at Murmur's inter-module boundaries, rather than anonymous maps
- [ ] `StoreArtifact.run/2` returns an `%Envelope{}` struct (not a plain map)
- [ ] `workspace_live` artifact signal handler stores data as `%Envelope{}` — not raw data
- [ ] All `unwrap_envelope/1` fallback clauses are removed; renderers pattern-match on `%Envelope{data: inner}` only
- [ ] Existing persisted checkpoints from before ticket 009 are intentionally discarded during rollout; no adaptive loading or version-branch fallback is added
- [ ] Both live-update and page-reload paths produce identical `%Envelope{}` shapes for the same artifact

### Checkpoint serialization (P1)

- [ ] Checkpoint persistence continues to use `:erlang.term_to_binary` for Murmur's internal Elixir state
- [ ] No JSON-specific encoder or decoder is required for `%Envelope{}` checkpoint round-tripping
- [ ] `%Envelope{}` survives hibernate/thaw without shape conversion code

### Integration tests (P1)

- [ ] Integration tests exist for each artifact type exercising the full `StoreArtifact` → renderer path
- [ ] Tests cover both signal-driven data (live path) and newly persisted enveloped data written after the 009 rollout
- [ ] Tests verify the artifact badge counts, labels, and rendered content are correct

### SQL result struct (P2)

- [ ] `JidoSql.QueryResult` struct exists with `@enforce_keys` and `@type t`
- [ ] `QueryExecutor.execute/3` returns `{:ok, %QueryResult{}}` or `{:error, reason}`
- [ ] All consumers of `QueryExecutor` results are updated to pattern-match on `%QueryResult{}`

### Typespecs & manual Dialyzer (P2)

- [ ] `"dialyzer"` is not added to the `precommit` alias in the root `mix.exs`
- [ ] `mix dialyzer` remains available as an explicit manual command
- [ ] `.dialyzer_ignore.exs` exists only if needed to document known false positives
- [ ] `mix dialyzer` exits with zero errors on a clean build
- [ ] `@spec` annotations exist on all public functions in: `JidoArtifacts.Artifact`, `JidoArtifacts.Envelope`, `JidoSql.QueryExecutor`, `JidoMurmur.Runner`, `JidoMurmur.UITurn`
- [ ] `@spec` annotations exist on all public functions in: `JidoTasks` context module, `JidoMurmur.Storage.Ecto`

### Signal data typing (P3)

- [ ] At least the `artifact.*`, `murmur.message.*`, and `task.*` signal families define typed schemas (not `:any`)
- [ ] No changes are required in the Jido framework to support ticket 009
- [ ] Consumers can pattern-match on the typed signal data without defensive fallbacks

## Scope

### In Scope

- `JidoArtifacts.Envelope` struct definition and migration of all producers/consumers
- Unification of live-update and persistence artifact data paths in `workspace_live`
- One-time clean cutover for persisted checkpoints created before the `%Envelope{}` rollout
- Retaining `:erlang.term_to_binary` as the internal checkpoint encoding for `%Envelope{}` and other Elixir state
- `JidoSql.QueryResult` struct definition and migration of all producers/consumers
- Integration tests for artifact rendering pipeline
- `@spec` annotations on public APIs at inter-app boundaries
- Typed signal data schemas for artifact, message, and task signal families

### Out of Scope

- Runtime schema validation libraries (e.g., `NimbleOptions` for arbitrary map validation) — we rely on structs and Dialyzer instead
- Migrating existing Ecto schemas — they already provide type guarantees through Ecto
- Full typespec coverage of all internal/private functions — only inter-module boundaries
- Modifying the Jido framework's signal infrastructure itself — we work within its current `use Jido.Signal` pattern
- Creating a generic "data contract" library or DSL — use plain Elixir structs
- Changing checkpoint persistence to JSON for internal Murmur state
- Performance benchmarking of Dialyzer PLT build times
- Backward-compatible loading of persisted checkpoints created before the 009 rollout
