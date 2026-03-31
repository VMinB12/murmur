# Data Contract Enforcement

How to catch data-shape mismatches (like the artifact envelope bug) before they reach production.

## The Problem

Murmur passes structured data across module boundaries without formal contracts. The artifact system is the worst offender:

1. **StoreArtifact** wraps data in `%{data: ..., version: ..., updated_at: ..., source: ...}`
2. **workspace_live signal handler** strips the envelope on live updates (stores raw data)
3. **Persistence path** preserves the envelope when loading from checkpoints
4. **Renderers** must handle both wrapped and unwrapped data via `unwrap_envelope/1` fallbacks

This means the same renderer can see two completely different data shapes depending on whether the page was loaded fresh (persisted envelope) or received a live update (raw data). Bugs appear only in one path, making them hard to reproduce.

The envelope mismatch is one instance of a broader pattern: every inter-module data handoff is an untyped `map()` or `:any` with no compile-time or test-time validation of shape.

---

## Recommendations

### 1. Add Dialyzer to precommit (low effort, moderate ROI)

Dialyzer is already a dependency but is not in the precommit alias. Adding it catches a class of type errors at compile time — but only if typespecs exist.

```elixir
# mix.exs
precommit: [
  "compile --warnings-as-errors",
  "deps.unlock --unused",
  "format",
  "dialyzer",          # ← add
  "test",
  "credo --strict",
  "sobelow --root apps/murmur_demo --config"
]
```

**Tradeoffs:**
- ✅ Zero new dependencies — already in deps
- ✅ Catches function clause mismatches, missing map keys, wrong return types
- ❌ First run builds PLT (~5-10 min), subsequent runs ~30-60s
- ❌ Useless without typespecs — requires effort to annotate the critical paths
- ❌ Can produce false positives, requiring a `.dialyzer_ignore.exs` allowlist

**Verdict:** Add it, but it's not sufficient alone. Dialyzer is best at catching "this function can never match" errors, not "this map might or might not have a `:data` key."

### 2. Define typed structs for inter-module data (medium effort, high ROI)

Replace the implicit envelope map with a struct:

```elixir
defmodule JidoArtifacts.Envelope do
  @enforce_keys [:data, :version, :source, :updated_at]
  defstruct [:data, :version, :source, :updated_at]

  @type t :: %__MODULE__{
          data: term(),
          version: pos_integer(),
          source: String.t(),
          updated_at: DateTime.t()
        }
end
```

Then `StoreArtifact` returns `%Envelope{}` instead of a plain map. Any code that pattern-matches on `%{data: inner}` will crash immediately when receiving a non-envelope — there's no silent fallback.

**Where to apply this pattern:**
- `JidoArtifacts.Envelope` — the artifact wrapper
- `JidoSql.QueryExecutor` result — `%{columns: [...], rows: [...], total_rows: n}` → struct
- `JidoMurmur.UITurn` / `ToolCall` — already a struct (good example to follow)

**Tradeoffs:**
- ✅ `@enforce_keys` fails loudly at construction time if a field is missing
- ✅ Structs don't implement `Access` — `envelope[:data]` becomes a compile error, forcing explicit `.data`
- ✅ Dialyzer can validate struct field types
- ✅ Pattern matching on `%Envelope{data: inner}` is unambiguous
- ❌ Requires updating all producers and consumers (migration effort)
- ❌ Structs don't serialize through JSON or `:erlang.term_to_binary` as cleanly — checkpoint persistence code needs adjustment

**Verdict:** Highest impact change. Start with `Envelope` since it's the source of the most recent bugs.

### 3. Integration tests for artifact rendering pipeline (medium effort, high ROI)

The current tests for artifact components use hardcoded raw maps — they don't exercise the actual data flow from `StoreArtifact` → persistence → renderer. Add a small integration test module:

```elixir
defmodule MurmurWeb.ArtifactRenderingTest do
  use MurmurWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "sql_results badge renders from enveloped artifact data" do
    envelope = %{
      data: [%{sql: "SELECT 1", label: "SELECT 1", row_count: 1, column_count: 1}],
      version: 1,
      source: "test",
      updated_at: DateTime.utc_now()
    }

    html =
      render_component(&MurmurWeb.Components.Artifacts.artifact_badge/1,
        name: "sql_results",
        data: envelope,
        session_id: "sess-1",
        active?: false
      )

    assert html =~ "1 query"
  end
end
```

This would have caught the envelope bug immediately — the `List.wrap` on a map produces `[map]`, making the badge show "1 query" regardless of actual count.

**Tradeoffs:**
- ✅ Catches exactly the class of bug we hit (shape mismatch between producer and renderer)
- ✅ Fast to run, no external deps
- ✅ Documents the expected contract between StoreArtifact and renderers
- ❌ Doesn't prevent the bug at compile time — only catches it when tests run
- ❌ Must be maintained as artifact types are added

**Verdict:** Essential complement to typespecs. Cheap insurance.

### 4. Normalize the data path (medium effort, highest ROI)

The root cause is that `workspace_live.handle_info` for artifact signals stores data in a **different shape** than the persistence path. Fix this by always wrapping in the envelope, even on the live path:

```elixir
# workspace_live.ex — artifact signal handler
def handle_info(%Jido.Signal{type: "artifact." <> _name} = signal, socket) do
  # Let StoreArtifact handle ALL wrapping — just read from agent state
  # instead of re-parsing signals in the LiveView
end
```

Or at minimum, ensure the live handler produces the same envelope shape that `StoreArtifact` produces.

**Tradeoffs:**
- ✅ Single source of truth for artifact shape — StoreArtifact only
- ✅ Eliminates the need for `unwrap_envelope` fallback clauses
- ❌ Requires careful testing of both live and reload paths
- ❌ May change timing/ordering of UI updates

**Verdict:** The fix we should have always had. Unifying the paths eliminates the entire category of bug.

---

## Prioritized Action Plan

| Priority | Action | Effort | Impact |
|----------|--------|--------|--------|
| **P0** | Normalize live + persistence artifact paths | Medium | Eliminates root cause |
| **P1** | `Envelope` struct with `@enforce_keys` | Low | Catches misuse at construction |
| **P2** | Integration tests for artifact rendering | Low | Catches mismatches in CI |
| **P3** | Add Dialyzer to precommit | Low | Catches broader type errors |
| **P4** | Typespecs on all inter-module boundaries | Ongoing | Maximizes Dialyzer coverage |

If doing only one thing: **P0 + P1** together. Struct + single data path eliminates the bug class entirely.

If optimizing for CI safety net: **P2 + P3**. Integration tests catch shape mismatches; Dialyzer catches type mismatches.
