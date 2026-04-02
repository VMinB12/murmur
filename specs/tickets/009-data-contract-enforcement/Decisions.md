# Decisions: Data Contract Enforcement

## Open

_(none)_

## Resolved

### Clarification: Envelope vs serialization format

**Context**: Two separate design questions were being discussed together:

1. What shape should artifact data have inside Murmur?
2. How should Murmur persist that shape in checkpoints?

This created confusion because `%Envelope{}` and `:erlang.term_to_binary` are not competing options.

**Decision**: `%Envelope{}` is the canonical in-memory data contract for artifacts. `:erlang.term_to_binary` is the checkpoint serialization format used to persist that contract. The intended flow is: artifact payload -> `%Envelope{}` in memory -> `:erlang.term_to_binary` at checkpoint write -> `%Envelope{}` again after thaw.

### Q1: How should existing persisted artifacts be handled?

**Context**: Artifacts already stored in PostgreSQL checkpoints use plain maps (`%{data: ..., version: ..., source: ..., updated_at: ...}`). When the system thaws these, they won't be `%Envelope{}` structs. We need a migration strategy.

**Options**:
1. **Adaptive loading** — Add a `from_map/1` constructor on `Envelope` that converts plain maps on thaw. Existing data is converted on read, no DB migration needed. Downside: the conversion code lives forever.
2. **Data migration** — Write a one-time Ecto migration that rewrites persisted checkpoints. Clean slate, but complex because checkpoint data is serialized (`:erlang.term_to_binary` or JSON). Risky if format varies.
3. **Version flag** — Store a format version in the checkpoint. Thaw logic branches on version: v1 = plain map, v2 = struct. Clean separation, but adds permanent branching in the thaw path.

**Suggested**: If backward compatibility matters, Option 1 is the cheapest transition. If it does not, a hard cutover is more robust.

**Decision**: Use a hard cutover. Existing checkpoints created before ticket 009 will be discarded as part of the rollout, with no adaptive loader, migration, or version flag. This is the simplest and most robust choice because it leaves a single artifact contract in the system after rollout: `%Envelope{}`.

### Q2: Should `%Envelope{}` serialize cleanly through the persistence layer?

**Context**: Once `%Envelope{}` is the canonical in-memory contract, Murmur still needs an encoding format for checkpoint persistence. Elixir structs don't serialize to JSON the same way plain maps do (the `__struct__` key is included). If checkpoints use `:erlang.term_to_binary`, structs round-trip fine. If they use JSON, we need `Jason.Encoder` or a custom serializer.

**Options**:
1. **Derive `Jason.Encoder`** — Add `@derive Jason.Encoder` to the struct. JSON output omits `__struct__`, making it compatible with existing consumers. Requires `from_map/1` on deserialization.
2. **Keep `:erlang.term_to_binary`** — If the persistence layer already uses Erlang term format, structs round-trip transparently with no extra work.
3. **Custom protocol** — Implement a custom `encode/decode` protocol. Maximum control, but unnecessary complexity for this use case.

**Suggested**: For internal Elixir-only checkpoints, prefer Erlang terms. For public APIs or cross-language interchange, prefer JSON.

**Decision**: Keep `:erlang.term_to_binary` for checkpoint payloads. Murmur already serializes checkpoints that way inside the JSONB row wrapper, so `%Envelope{}` will round-trip cleanly with no custom encoder. This is the best fit for internal persistence because it is lossless for Elixir structs and avoids JSON-specific conversion code. The JSON vs `:erlang.term_to_binary` choice is a persistence-format decision, not a replacement for `%Envelope{}`.

### Q3: How strict should Dialyzer be in precommit?

**Context**: Dialyzer can produce false positives, especially in dynamic Elixir code interacting with external libraries. If we treat all warnings as errors in precommit, developers may be blocked by warnings in upstream deps or generated code.

**Options**:
1. **Warnings as errors from day one** — Add `--halt-exit-status` (default) and maintain a `.dialyzer_ignore.exs` allowlist for known false positives. Strictest, but requires upfront effort to triage initial warnings.
2. **Advisory mode first** — Add Dialyzer to precommit but don't fail on warnings initially. Use an allow-listed set of warning types (e.g., only `:error_handling` and `:no_return`). Gradualy tighten.
3. **Per-app opt-in** — Only run Dialyzer on apps with significant typespec coverage (`jido_artifacts`, `jido_sql`). Other apps opt in later.

**Suggested**: If fast local commit flow is a priority, keep Dialyzer explicit rather than automatic.

**Decision**: Do not add Dialyzer to precommit. Keep `mix dialyzer` as a manual tool for focused static analysis, but do not make it part of the default local commit pipeline.

### Q4: Should we use `TypedStruct` or plain `defstruct` + `@enforce_keys`?

**Context**: The `typed_struct` Hex package provides a DSL for defining structs with types and enforced keys in one declaration. Plain Elixir requires separate `@enforce_keys`, `defstruct`, and `@type` declarations.

**Options**:
1. **Plain Elixir** — `@enforce_keys` + `defstruct` + `@type t`. No new dependency. Standard, but slightly verbose.
2. **`TypedStruct`** — `typedstruct do field :data, term(), enforce: true end`. Less boilerplate, but adds a compile-time dependency. Less discoverable for contributors unfamiliar with the library.

**Suggested**: Option 1 unless the project begins defining many repetitive structs. `TypedStruct` mainly improves declaration ergonomics; it does not add runtime validation, stronger serialization guarantees, or stronger type checking than plain Elixir.

**Decision**: Use plain Elixir (`@enforce_keys`, `defstruct`, and `@type t`). For the small number of structs in scope for ticket 009, `TypedStruct` adds little beyond syntactic sugar.

### Q5: Scope of signal data typing (P3)

**Context**: The Jido framework's `use Jido.Signal` macro currently allows `:any` as a field type in signal schemas. Tightening this affects how signals are defined across the entire project. We could type just our signal schemas, or push for a framework-level change.

**Options**:
1. **Application-level typing only** — Define stricter schemas in Murmur's signal modules (e.g., `field :task, JidoTasks.Task.t()` instead of `:any`). Works within the current Jido API but doesn't enforce at the framework level.
2. **Framework-level enforcement** — Propose a Jido change that validates signal data against schemas at emission time. Broader impact, but requires coordinating with the Jido framework roadmap.
3. **Defer entirely** — Mark P3 as future work. Focus on struct enforcement (P1/P2) first — it covers the most impactful cases. Revisit signal typing after the foundation is solid.

**Suggested**: Option 1 for now. Define typed schemas in our signal modules. This gives us documentation and Dialyzer coverage without a framework dependency. We can propose framework-level enforcement as a separate Jido ticket later.

**Decision**: Use application-level typing only. Murmur signal modules should define concrete field types instead of `:any`, but ticket 009 will not depend on Jido changing its framework-level validation behavior.
