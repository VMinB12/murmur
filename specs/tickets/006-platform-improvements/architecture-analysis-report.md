# Architecture Analysis Report

**Date**: 2026-03-29
**Scope**: jido_murmur ecosystem — artifact extraction, Igniter adoption, CloudEvents alignment, and improvement opportunities

---

## Table of Contents

1. [Artifact Plugin Extraction](#1-should-artifact-plugins-be-extracted-into-a-separate-library)
2. [Igniter Adoption](#2-should-we-adopt-igniter-for-our-packages)
3. [CloudEvents & jido_signal Alignment](#3-are-we-properly-leveraging-jido_signal-and-cloudevents)
4. [Additional Improvement Opportunities](#4-additional-improvement-opportunities)
5. [Artifact System Design Review](#5-artifact-system-design-review)

---

## 1. Should Artifact Plugins Be Extracted into a Separate Library?

### Current State

The artifact system lives in jido_murmur and consists of three modules:

| Module | Role | Lines |
|--------|------|-------|
| `JidoMurmur.Artifact` | Signal creation helper (`emit/4`), topic builder | ~50 |
| `JidoMurmur.ArtifactPlugin` | Jido Plugin — intercepts `artifact.*` signals, PubSub broadcast, override routing | ~60 |
| `JidoMurmur.Actions.StoreArtifact` | Jido Action — merges artifact data into agent state | ~40 |

Cross-app consumers:
- **jido_arxiv** — `ArxivSearch` and `DisplayPaper` call `Artifact.emit/4` to produce artifact directives
- **jido_murmur_web** — `ArtifactPanel` component renders artifacts in the UI
- **murmur_demo** — Agent profiles include `ArtifactPlugin` in their plugin lists

The artifact signal flow:

```
Tool Action (e.g., ArxivSearch)
  → Artifact.emit(ctx, "papers", papers, mode: :append)
    → Returns %Directive.Emit{signal: Jido.Signal}
      → AgentServer processes directive, emits signal
        → ArtifactPlugin.handle_signal/2 intercepts
          1. PubSub broadcast: {:artifact_update, session_id, name, data, mode}
          2. Override: {:ok, {:override, {StoreArtifact, params}}}
            → StoreArtifact merges into agent.state.artifacts
```

### Design Intent: Artifacts as the Primary Domain Tool Interface

While only jido_arxiv and jido_tasks exist today, **artifacts are the designed standard for domain tools to expose structured data to the frontend**. The pattern is intentionally generic:

1. A tool action runs (search, analysis, code generation, data fetch, etc.)
2. It calls `Artifact.emit(ctx, name, data, mode:)` to produce a signal
3. `ArtifactPlugin` intercepts, persists in agent state, and broadcasts to the UI
4. `ArtifactPanel` (jido_murmur_web) renders the data with pluggable renderers

This means virtually every future domain tool package — whether it's a code analysis plugin, a data visualization tool, a document generator, or anything else — will need `Artifact.emit/4` to surface results in the frontend. The artifact system is not a utility used by one package; it's the **contract between tool actions and the UI layer**.

### Analysis

**Arguments FOR extraction** (into e.g. `jido_artifacts`):

1. **Dependency inversion (critical at scale)** — Every future domain tool package would depend on jido_murmur just for `Artifact.emit/4`. This forces every lightweight tool to pull in Runner, PendingQueue, Storage, TeamInstructions, MessageInjector, and the entire orchestration layer. With N tool packages, this becomes N unnecessary heavy dependencies.
2. **Artifacts are the ecosystem's shared primitive** — The artifact system is a domain-agnostic pattern (signal → intercept → store → broadcast) that functions as the standard data-to-UI contract. Shared primitives belong in shared packages, not bundled inside a specific orchestration layer.
3. **Clean package semantics** — `jido_artifacts` communicates "this package handles structured data artifacts" clearly. Tool authors `{:jido_artifacts, "~> 0.1"}` in their deps and get exactly what they need — nothing more.
4. **Parallel to jido ecosystem structure** — Jido itself separates concerns: `jido` (core), `jido_signal` (events), `jido_action` (tools), `jido_ai` (reasoning). Extracting `jido_artifacts` follows the same philosophy: a focused package for a focused concern.
5. **Unblocks independent tool development** — Third-party developers building Jido tool packages can depend on `jido_artifacts` without needing to understand or depend on the full Murmur orchestration.

**Arguments AGAINST extraction:**

1. **Surface area is tiny** — ~150 lines across 3 modules. That's a very small package to version, test, document, and publish independently.
2. **Tight coupling to agent state** — `StoreArtifact` writes into `agent.state.artifacts`, which is persisted by jido_murmur's `Storage.Ecto`. Extracting artifacts means the action either stays in jido_murmur (splitting the abstraction) or the extracted package needs a storage adapter pattern.
3. **PubSub dependency** — `ArtifactPlugin` broadcasts via `JidoMurmur.pubsub()`. An extracted package would need its own config accessor or accept PubSub as a parameter.

### Recommendation: **Yes, extract into `jido_artifacts` — do it now while the API surface is small.**

The original analysis recommended deferring extraction and waiting for a "Rule of Three" trigger. With the context that artifacts are the **designed standard pattern** for all future domain tools, that trigger is already met by design intent. Every future tool package is a consumer. Waiting until 3+ packages depend on jido_murmur for this one helper function would create technical debt that's harder to unwind post-publish.

Extracting now is cheap because:
- The API is tiny and stable (~150 lines, well-tested)
- No published packages means zero breaking changes for consumers
- The module boundaries are already clean (3 modules, no entanglement with Runner/Storage internals)

### Extraction Plan

**Package**: `jido_artifacts`
**Dependencies**: `jido ~> 2.0`, `jido_signal ~> 2.0`, `jido_action ~> 2.0`, `phoenix_pubsub ~> 2.0`

```
apps/jido_artifacts/
├── lib/
│   ├── jido_artifacts.ex            # Config accessors (pubsub)
│   ├── jido_artifacts/
│   │   ├── artifact.ex              # emit/4 helper, topic builder
│   │   ├── artifact_plugin.ex       # Jido Plugin — signal interception
│   │   └── actions/
│   │       └── store_artifact.ex    # Jido Action — state merge
│   └── mix/
│       └── tasks/
│           └── jido_artifacts.install.ex  # (Igniter) config setup
├── test/
│   ├── jido_artifacts/
│   │   ├── artifact_test.exs
│   │   ├── artifact_plugin_test.exs
│   │   └── actions/
│   │       └── store_artifact_test.exs
│   └── test_helper.exs
└── mix.exs
```

**Module naming**: `JidoArtifacts.Artifact`, `JidoArtifacts.ArtifactPlugin`, `JidoArtifacts.Actions.StoreArtifact`

**Config**: `config :jido_artifacts, pubsub: MyApp.PubSub`

**Dependency graph after extraction:**

```
jido_murmur ──depends──→ jido_artifacts
jido_arxiv  ──depends──→ jido_artifacts   (instead of jido_murmur)
jido_tasks  ──depends──→ jido_artifacts   (if tasks emit artifacts in future)
jido_murmur_web ──depends──→ jido_artifacts (for topic helpers)
```

**Key design decisions:**

1. **StoreArtifact stays in the extracted package** — It writes to `agent.state.artifacts`, which is a plain map key in agent state. This doesn't depend on jido_murmur's Storage.Ecto; the Jido checkpoint system handles persistence generically.
2. **PubSub config moves to `:jido_artifacts`** — The plugin broadcasts on its own config, not jido_murmur's. jido_murmur's install task can set both configs to the same PubSub module.
3. **Backward compatibility** — jido_murmur re-exports or aliases the extracted modules for existing consumers during a transition period (optional, since nothing is published yet).

**Migration steps:**

1. Apply API changes from Section 5 first (metadata, ctx usage, scope concept)
2. Create `apps/jido_artifacts/` with the updated modules + tests
3. Update jido_murmur to depend on `jido_artifacts` and remove the 3 original modules
4. Update jido_arxiv to depend on `jido_artifacts` instead of jido_murmur
5. Update jido_murmur_web to depend on `jido_artifacts` for topic helpers
6. Update murmur_demo agent profiles to use `JidoArtifacts.ArtifactPlugin`
7. Update config to include `:jido_artifacts` pubsub setting
8. Run full test suite

---

## 2. Should We Adopt Igniter for Our Packages?

### Current State

**Our packages**: Use plain `Mix.Task` + `Mix.Generator` for install tasks:
- `mix jido_murmur.install` — generates 4 migration files
- `mix jido_tasks.install` — generates 1 migration file
- `mix jido_murmur_web.install <group>` — copies component files

**Jido ecosystem**: All core packages declare `{:igniter, "~> 0.7", optional: true}` and provide Igniter-based tasks:
- `mix igniter.install jido` — configures app, creates Jido module, adds to supervisor tree
- `mix jido.gen.agent` — scaffolds agent modules
- `mix jido.gen.plugin` — scaffolds plugin modules
- `mix jido.gen.sensor` — scaffolds sensor modules
- `mix jido_action.gen.action` — scaffolds action modules
- `mix jido_action.gen.workflow` — scaffolds workflow/plan modules
- `mix jido_signal.install` — shows getting-started guide
- `mix jido_ai.install` — sets up jido_ai

Jido uses a **guard pattern** to make Igniter optional:

```elixir
if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Jido.Install do
    use Igniter.Mix.Task
    # Full Igniter implementation
  end
else
  defmodule Mix.Tasks.Jido.Install do
    use Mix.Task
    def run(_argv) do
      Mix.shell().error("igniter is required...")
    end
  end
end
```

Phoenix LiveView also supports Igniter (`{:igniter, ">= 0.6.16 and < 1.0.0-0", optional: true}`).

### Analysis

**Arguments FOR adopting Igniter now:**

1. **Ecosystem alignment** — Every Jido package uses Igniter. Users doing `mix igniter.install jido` expect the same DX for jido_murmur. Being the outlier creates friction.
2. **Superior install experience** — Igniter can:
   - Modify `config.exs` programmatically (add `:jido_murmur` config block)
   - Add modules to supervision trees automatically
   - Generate migrations AND run them
   - Chain installers: `mix igniter.install jido_murmur` could trigger `jido.install` if not already set up
   - Show diffs and ask for confirmation before writing
3. **Clean migration window** — No published packages means zero breaking changes. If we publish with Mix.Task and later switch to Igniter, we'd need to maintain both or break existing users.
4. **Generator potential** — Beyond install, Igniter enables rich generators:
   - `mix jido_murmur.gen.profile` — scaffold an agent profile with plugins pre-configured
   - `mix jido_murmur.gen.artifact_renderer` — scaffold a custom artifact renderer
   - `mix jido_tasks.gen.tool` — scaffold a new task board tool
5. **The Jido guard pattern makes it zero-risk** — Igniter is optional. Users without it get a clear error message. No hard dependency.

**Arguments AGAINST:**

1. **Additional dependency** — Igniter pulls in `sourceror`, `rewrite`, `spitfire`, and other AST manipulation deps. While optional, it increases the dep tree for users who want it.
2. **Complexity** — Igniter's AST-aware code generation is more complex to write and test than simple template copying. Our current install tasks are ~100 lines each and straightforward.
3. **Current tasks work fine** — The migration generators are functional and tested. "If it ain't broke" applies.
4. **Learning curve** — Team needs to learn Igniter's API (`Igniter.Project.Config`, `Igniter.Project.Application`, `Igniter.Project.Module`).

**Cost comparison:**

| Capability | Current (Mix.Task) | With Igniter |
|-----------|-------------------|-------------|
| Generate migrations | ✅ Template copying | ✅ Same, but can chain |
| Configure config.exs | ❌ Manual step | ✅ Automatic |
| Add to supervisor | ❌ Manual step | ✅ Automatic |
| Generate modules | ❌ Not implemented | ✅ Code-aware scaffolding |
| Chain installers | ❌ Not possible | ✅ `mix igniter.install A B C` |
| Diff preview | ❌ Not possible | ✅ Built-in |
| Idempotent re-run | ⚠️ Partial (skip existing) | ✅ Full AST-level detection |

### Recommendation: **Yes, adopt Igniter now. Use the optional guard pattern.**

The alignment with the Jido ecosystem, the clean migration window, and the superior DX make this the right time. The guard pattern means it's zero-risk — Igniter stays optional.

### Implementation Plan

**Phase 1: Convert existing install tasks to Igniter**

```elixir
# apps/jido_murmur/mix.exs
defp deps do
  [
    # ... existing deps
    {:igniter, "~> 0.7", optional: true}
  ]
end
```

Each package install task:
1. `mix jido_murmur.install` (Igniter version):
   - Generate migrations (same as now)
   - Add config block to `config.exs`:
     ```elixir
     config :jido_murmur,
       repo: MyApp.Repo,
       pubsub: MyApp.PubSub,
       jido_mod: MyApp.Jido,
       otp_app: :my_app
     ```
   - Add `JidoMurmur.Supervisor` to application supervision tree
   - Chain: ensure `jido.install` has run first

2. `mix jido_tasks.install` (Igniter version):
   - Generate migration
   - Add config block:
     ```elixir
     config :jido_tasks,
       repo: MyApp.Repo,
       pubsub: MyApp.PubSub
     ```
   - Chain: ensure `jido_murmur.install` has run first (FK dependency)

3. `mix jido_murmur_web.install` (Igniter version):
   - Copy component files (same as now)
   - Optionally: inject import into the app's `html_helpers` block

**Phase 2: Add generators**

- `mix jido_murmur.gen.profile` — scaffolds agent profile module with tool/plugin configuration
- `mix jido_murmur.gen.artifact_renderer` — scaffolds custom artifact renderer

**Effort estimate**: Phase 1 is ~2-3 hours per package (mostly translating existing logic to Igniter API). Phase 2 is additive and can ship later.

---

## 3. Are We Properly Leveraging jido_signal and CloudEvents?

### Current State

**jido_signal v2.0.0** implements CloudEvents v1.0.2 with Jido extensions. The `Jido.Signal` struct:

```elixir
%Jido.Signal{
  specversion: "1.0.2",        # CloudEvents
  id: "...",                    # UUIDv7, required
  source: "...",                # URI-reference, required
  type: "...",                  # Dot-notation, required
  subject: nil,                 # Optional
  time: nil,                    # Optional
  datacontenttype: "application/json",  # Default
  dataschema: nil,              # Optional
  data: %{},                    # Payload
  extensions: %{},              # CloudEvents extensions
  jido_dispatch: nil            # Jido-specific routing
}
```

**Our usage of CloudEvents fields:**

| Field | Status | How We Use It |
|-------|--------|---------------|
| `specversion` | ✅ Implicit | Set to "1.0.2" by Signal.new! |
| `id` | ✅ Used | Auto-generated UUIDv7 |
| `source` | ⚠️ Partially | Only set for artifact signals (`"/artifact/papers"`). StreamingPlugin receives signals from Jido core which set source automatically. |
| `type` | ✅ Well used | Dot-notation convention: `"artifact.papers"`, `"ai.llm.delta"`, etc. |
| `subject` | ❌ Not used | Never explicitly set in any of our code |
| `time` | ❌ Not used | Never explicitly set (though jido_signal may auto-populate) |
| `datacontenttype` | ❌ Not used | Always defaults to "application/json" |
| `dataschema` | ❌ Not used | Never set |
| `data` | ✅ Well used | All signal payloads go through data field |
| `extensions` | ❌ Not used | Empty map by default |

**Our usage of jido_signal features:**

| Feature | Status | Notes |
|---------|--------|-------|
| Signal creation (`Signal.new!`) | ✅ | Used in `Artifact.emit/4` |
| Signal ID generation (`Signal.ID.generate!`) | ✅ | Used in UITurn, TellAction, AddTask for message/task IDs |
| Plugin signal patterns | ✅ | `signal_patterns: ["artifact.*"]`, `signal_patterns: ["ai.llm.*", ...]` |
| Custom signal types (`use Jido.Signal`) | ❌ | Zero uses in our codebase |
| Signal routing/dispatching | ⚠️ | We rely on Jido core's plugin dispatch; no custom routers |
| Signal serialization (JSON) | ⚠️ | Signals pass through PubSub as structs, not serialized |
| Signal schema validation | ❌ | No NimbleOptions schemas on our signal data |

### Analysis

**What we're doing right:**
- Type conventions follow CloudEvents dot-notation (`artifact.papers`, `ai.llm.delta`)
- Plugin pattern matching is idiomatic Jido
- Signal IDs use UUIDv7 (time-ordered, sortable) — good for replay/audit

**What we're missing:**

#### A. No Custom Signal Type Definitions

jido_signal provides `use Jido.Signal` for defining typed, validated signal modules:

```elixir
defmodule JidoMurmur.Signals.ArtifactEmitted do
  use Jido.Signal,
    type: "artifact.emitted",
    default_source: "/jido_murmur/artifact",
    schema: [
      name: [type: :string, required: true],
      data: [type: :any, required: true],
      mode: [type: {:in, [:replace, :append]}, default: :replace]
    ]
end
```

**Benefits of typed signals:**
- Compile-time validation of signal data shape
- Self-documenting signal catalog (tools can enumerate all signal types)
- Consistent source URIs across all emission points
- Pattern matching on module names instead of magic strings

**Tradeoff:** More boilerplate for what's currently 3-4 signal types.

#### B. Underutilized `subject` Field

CloudEvents `subject` identifies the entity the event is about. This maps naturally to our domain:

| Signal Type | Natural Subject |
|-------------|----------------|
| `artifact.papers` | `"/sessions/{session_id}/agents/{agent_id}"` |
| `ai.llm.delta` | `"/sessions/{session_id}"` |
| Task events | `"/workspaces/{workspace_id}/tasks/{task_id}"` |

This would enable:
- Filtering signals by entity without parsing data payloads
- Standard CloudEvents routing on subject
- Interoperability with external systems (e.g., webhook receivers)

#### C. PubSub Messages Are Not Signals

Currently, PubSub broadcasts use ad-hoc tuples:

```elixir
# Current patterns:
{:artifact_update, session_id, artifact_name, artifact_data, mode}
{:agent_signal, session_id, signal}
{:message_completed, session_id, response}
{:task_created, task}
{:new_message, target_session_id, inter_msg}
```

Only `{:agent_signal, session_id, signal}` wraps an actual `Jido.Signal`. The rest are raw tuples. This means:
- No consistent event envelope for PubSub consumers
- No signal ID, timestamp, or source for audit/replay on non-signal messages
- Mixing paradigms: signals for streaming, tuples for everything else

#### D. Signal ID Used for Non-Signal Purposes

`Jido.Signal.ID.generate!()` is used for general-purpose ID generation (message IDs in UITurn, inter-agent message tracking in TellAction). While this works (it generates UUIDv7), it's semantically overloaded. The function name implies signal context.

### Recommendation: **Incremental CloudEvents alignment in two phases**

#### Phase 1: Low-effort, high-value (do now)

1. **Set `subject` on artifact signals** — The session/agent context is available at emission time:
   ```elixir
   Jido.Signal.new!("artifact.papers", data, 
     source: "/artifact/papers",
     subject: "/sessions/#{session_id}")
   ```

2. **Standardize PubSub messages as signals** — Convert the 5 ad-hoc tuple patterns to proper Jido.Signal structs. This gives every PubSub message a type, source, id, and timestamp:
   ```elixir
   # Before:
   PubSub.broadcast(pubsub, topic, {:task_created, task})
   
   # After:
   signal = Jido.Signal.new!("task.created", %{task: task},
     source: "/jido_tasks",
     subject: "/workspaces/#{workspace_id}/tasks/#{task.id}")
   PubSub.broadcast(pubsub, topic, {:jido_signal, signal})
   ```
   
   LiveView handlers switch from `{:task_created, task}` to pattern-matching on `{:jido_signal, %{type: "task.created"} = signal}`.

3. **Replace `Jido.Signal.ID.generate!()` for non-signal IDs** — Use `Uniq.UUID.uuid7()` directly (already in deps via jido_signal) to avoid semantic confusion.

#### Phase 2: Structured signal catalog (do before v1.0)

1. **Define typed signal modules** for our core signal types using `use Jido.Signal`:
   - `JidoMurmur.Signals.ArtifactEmitted`
   - `JidoMurmur.Signals.MessageCompleted`
   - `JidoMurmur.Signals.RequestFailed`
   - `JidoTasks.Signals.TaskCreated`
   - `JidoTasks.Signals.TaskUpdated`

2. **Add signal schema documentation** — Each typed signal self-documents its data shape, making the event catalog discoverable.

3. **Consider `extensions` for Murmur-specific metadata** — CloudEvents extensions are the standard way to add domain context:
   ```elixir
   extensions: %{
     "murmursessionid" => session_id,
     "murmurworkspaceid" => workspace_id
   }
   ```

### Impact Assessment

| Change | Effort | Value | Risk |
|--------|--------|-------|------|
| Set `subject` on signals | Low | Medium | None |
| Standardize PubSub → signals | Medium | High | Medium (handler refactor) |
| Replace Signal.ID for non-signals | Low | Low | None |
| Typed signal modules | Medium | Medium | Low |
| CloudEvents extensions | Low | Low | None |

---

## 4. Additional Improvement Opportunities

### 4.1 PubSub Topic Inconsistency

Three different topic naming conventions are currently mixed:

```
"agent_artifacts:#{session_id}"          # colon-separated, no workspace
"agent_stream:#{session_id}"             # colon-separated, no workspace
"workspace:#{workspace_id}:agent:#{id}"  # colon-separated, hierarchical
"workspace:#{workspace_id}:tasks"        # colon-separated, hierarchical
```

The first two (used by plugins) are session-scoped but omit workspace context. The latter two (used by Runner and Tasks) include workspace hierarchy.

**Recommendation:** Standardize all topics to include workspace context and use consistent naming:

```
"murmur:#{workspace_id}:agent:#{session_id}:stream"
"murmur:#{workspace_id}:agent:#{session_id}:artifacts"
"murmur:#{workspace_id}:agent:#{session_id}:messages"
"murmur:#{workspace_id}:tasks"
```

Centralizing topic construction in a `JidoMurmur.Topics` module prevents string duplication:

```elixir
defmodule JidoMurmur.Topics do
  def agent_stream(workspace_id, session_id),
    do: "murmur:#{workspace_id}:agent:#{session_id}:stream"
  def agent_artifacts(workspace_id, session_id),
    do: "murmur:#{workspace_id}:agent:#{session_id}:artifacts"
  # ...
end
```

**Priority:** Medium. Do before v1.0 to avoid breaking changes after publish.

### 4.2 Missing `workspace_id` in Plugin Context

`ArtifactPlugin` and `StreamingPlugin` extract `session_id` from the signal but not `workspace_id`. This is fine for current session-scoped PubSub, but blocks the standardized topic scheme above and future multi-workspace features (Phase 3 shared artifacts from the architecture doc).

The plugins receive the agent state, which should include workspace context. Verify that `workspace_id` is available in the plugin context and thread it through to broadcasts.

**Priority:** Medium.

### 4.3 Telemetry Event Naming Convention

Current telemetry events:

```elixir
[:jido_murmur, :artifact, :store]
[:jido_murmur, :streaming, :signal]
[:jido_murmur, :runner, :loop_start]
[:jido_murmur, :runner, :send_message, :start/:stop/:exception]
```

These are reasonable but inconsistent with the jido_tasks package which doesn't emit telemetry events at all. The task tools (AddTask, UpdateTask, ListTasks) should emit telemetry for observability parity:

```elixir
[:jido_tasks, :task, :created]
[:jido_tasks, :task, :updated]
[:jido_tasks, :task, :listed]
```

**Priority:** Low. Nice-to-have for observability dashboards.

### 4.4 Config Validation at Startup

`JidoMurmur.repo()` calls `Application.fetch_env!(:jido_murmur, :repo)` which crashes with a generic error if config is missing. Jido upstream uses NimbleOptions for config validation with clear error messages.

Consider adding a `validate_config!/0` function called from `JidoMurmur.Supervisor.start_link/1`:

```elixir
def validate_config! do
  required = [:repo, :pubsub, :jido_mod, :otp_app]
  for key <- required do
    unless Application.get_env(:jido_murmur, key) do
      raise """
      Missing required configuration: config :jido_murmur, #{key}: ...
      
      Run `mix jido_murmur.install` to set up configuration.
      """
    end
  end
end
```

**Priority:** Medium. Improves first-run DX significantly.

### 4.5 Typed Agent Profile Behaviour

Agent profiles (e.g., `GeneralAgent`, `ArxivAgent`) are plain modules with conventions but no enforced contract. Consider defining a behaviour:

```elixir
defmodule JidoMurmur.Profile do
  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback system_prompt() :: String.t()
  @callback tools() :: [module()]
  @callback plugins() :: [module()]
  @callback opts() :: keyword()
end
```

This would:
- Enable compile-time validation of profiles
- Allow `Catalog` to call behaviour callbacks instead of relying on module attribute conventions
- Make it explicit what a "profile" needs to provide

**Priority:** Low. Current convention-based approach works. Consider for v1.0 if the profile count grows.

### 4.6 jido_arxiv Dependency Cleanup

With the artifact extraction (Section 1), jido_arxiv switches its dependency from jido_murmur to jido_artifacts. This gives it access to `JidoArtifacts.Artifact.emit/4` — the same helper, lighter dependency.

If the extraction hasn't happened yet as an interim step, jido_arxiv's two tools (`ArxivSearch`, `DisplayPaper`) can construct `%Directive.Emit{}` directly with `Jido.Signal.new!` to eliminate the jido_murmur dependency entirely:

```elixir
# Direct construction (no helper needed):
signal = Jido.Signal.new!("artifact.papers",
  %{name: "papers", data: papers, mode: :append},
  source: "/artifact/papers")
%Jido.Agent.Directive.Emit{signal: signal}
```

Any plugin that matches `"artifact.*"` (like ArtifactPlugin) will intercept these signals regardless of how they were constructed.

**Priority:** High. Superseded by Section 1 extraction if done; useful as interim step otherwise.

### 4.7 Documentation: Signal Event Catalog

There's no central documentation of all signal types used across the ecosystem. As packages multiply, consumers need to know:
- What signal types exist
- What data shapes they carry
- Which plugins handle them
- What PubSub topics they broadcast on

A `SIGNALS.md` in the docs/ directory (or generated from typed signal modules if Phase 2 of Section 3 is implemented) would serve as a developer reference.

**Priority:** Medium. Becomes more important as the signal count grows.

### 4.8 Test Helper Consolidation

Both jido_murmur and jido_tasks have test setup that configures repos, starts sandboxes, and mocks. The boilerplate could be extracted into a shared `JidoMurmur.TestHelper` module that consumer test suites call:

```elixir
# In consumer's test_helper.exs:
JidoMurmur.TestHelper.setup(repo: MyApp.Repo)
```

This aligns with the Igniter adoption — the install task could generate the test helper config automatically.

**Priority:** Low. Helpful for DX but not blocking.

---

## Summary Matrix

| Topic | Recommendation | Priority | Effort | Risk |
|-------|---------------|----------|--------|------|
| Artifact extraction | **Yes, extract `jido_artifacts` now** | High | Medium | Low |
| Artifact API changes | **Yes** — metadata, ctx, scope (Section 5) | High | Medium | Low |
| Igniter adoption | **Yes, adopt now** (optional dep, guard pattern) | High | Medium | Low |
| CloudEvents Phase 1 | **Yes** — subject, standardize PubSub, fix ID usage | High | Low-Medium | Low |
| CloudEvents Phase 2 | **Yes** — typed signals before v1.0 | Medium | Medium | Low |
| PubSub topic standardization | **Yes** — before v1.0 | Medium | Low | Medium |
| Plugin workspace_id threading | **Yes** — before v1.0 | Medium | Low | Low |
| Telemetry in jido_tasks | Nice-to-have | Low | Low | None |
| Config validation at startup | **Yes** | Medium | Low | None |
| Agent profile behaviour | Consider for v1.0 | Low | Low | None |
| jido_arxiv independence | Superseded by artifact extraction | — | — | — |
| Signal event catalog doc | **Yes** — before v1.0 | Medium | Low | None |
| Test helper consolidation | Nice-to-have | Low | Low | None |

### Recommended Execution Order

1. **Now (pre-publish):**
   - Artifact API changes: metadata wrapper, `emit/4` ctx usage, scope concept (Section 5)
   - Extract `jido_artifacts` package (Section 1) — artifacts are the core tool→UI contract, every future domain tool will need this
   - Add Igniter as optional dep, convert install tasks (Section 2)
   - Set `subject` on artifact signals, replace `Signal.ID.generate!()` for non-signals (Section 3, Phase 1, items 1 & 3)
   - Add config validation (Section 4.4)

2. **Before v1.0:**
   - Standardize PubSub messages as signals (Section 3, Phase 1, item 2)
   - Standardize PubSub topics (Section 4.1)
   - Thread workspace_id through plugins (Section 4.2)
   - Define typed signal modules (Section 3, Phase 2)
   - Write SIGNALS.md catalog (Section 4.7)
   - Shared artifact implementation if needed (Section 5.5)

3. **Post-v1.0 (as needed):**
   - Agent profile behaviour (Section 4.5)
   - Telemetry in jido_tasks (Section 4.3)
   - Test helper consolidation (Section 4.8)

---

## 5. Artifact System Design Review

A detailed review of the current artifact implementation, covering API design, data model, persistence, and scope. These decisions should be resolved **before** the `jido_artifacts` extraction (Section 1) since they affect the published API surface.

See also: [artifact-persistence.md](artifact-persistence.md), [artifact-panel-ui.md](artifact-panel-ui.md)

### 5.1 Merge Strategy: Replace `mode` with a Developer-Controlled `merge` Callback

**Problem:** `StoreArtifact` currently has hardcoded `:replace` and `:append` modes. `:append` does `existing ++ List.wrap(data)` with no limit, growing indefinitely. Adding `:max_items` or `:clear` as additional options leads to a combinatorial API that still can't cover every use case (prepend, dedup-by-ID, merge-by-key, windowed retention, etc.).

**Decision: Drop the `mode` parameter entirely. Replace it with a `merge` callback.**

The `merge` option accepts a function `(existing_data, new_data) -> merged_data` that gives the tool author full control over how new data combines with existing data. The framework provides built-in helpers for common patterns.

**API:**

```elixir
# Default: replace (no merge option needed)
Artifact.emit(ctx, "displayed_paper", paper)

# Append:
Artifact.emit(ctx, "papers", papers, merge: &Artifact.Merge.append/2)

# Append with limit (keep last 50):
Artifact.emit(ctx, "papers", papers, merge: &Artifact.Merge.append_max(50)/2)

# Prepend:
Artifact.emit(ctx, "papers", papers, merge: &Artifact.Merge.prepend/2)

# Dedup by ID field:
Artifact.emit(ctx, "papers", papers, merge: &Artifact.Merge.upsert_by(:id)/2)

# Clear (remove artifact):
Artifact.emit(ctx, "papers", nil, merge: fn _, _ -> nil end)

# Custom:
Artifact.emit(ctx, "results", new_results, merge: fn existing, new ->
  (existing ++ new) |> Enum.uniq_by(& &1.id) |> Enum.take(-100)
end)
```

**Built-in merge helpers** (in `Artifact.Merge` module):

```elixir
defmodule Artifact.Merge do
  def append(existing, new), do: existing ++ List.wrap(new)
  def prepend(existing, new), do: List.wrap(new) ++ existing

  def append_max(max) do
    fn existing, new -> Enum.take(existing ++ List.wrap(new), -max) end
  end

  def prepend_max(max) do
    fn existing, new -> Enum.take(List.wrap(new) ++ existing, max) end
  end

  def upsert_by(key) do
    fn existing, new ->
      index = Map.new(existing, &{Map.get(&1, key), &1})
      merged = Enum.reduce(List.wrap(new), index, fn item, acc ->
        Map.put(acc, Map.get(item, key), item)
      end)
      Map.values(merged)
    end
  end
end
```

**How `StoreArtifact` uses it:**

When no `merge` is provided, the new data replaces the existing data (current `:replace` behavior). When `merge` is provided, it receives the existing artifact data and the new data, and the return value becomes the new artifact data. If the merge function returns `nil`, the artifact is deleted (replacing the need for a `:clear` mode).

**Why this is better than `mode` + `max_items`:**

- **One primitive instead of three** — `merge` replaces `:mode`, `:max_items`, and `:clear` with a single concept
- **Fully extensible** — Tool authors aren't limited to framework-provided modes. They can implement any merge strategy: windowed retention, dedup, priority-based eviction, etc.
- **Composable** — Merge functions can be composed: `fn e, n -> e |> append(n) |> Enum.take(-50) end`
- **Serializable concern** — The merge function is only used at emit-time in the action. It flows through the signal as a flag (`:has_merge`) and the actual function reference is resolved by `StoreArtifact` from the signal data. This avoids serializing anonymous functions in signals.

**Serialization note:** Anonymous functions can't be serialized in signals. The `merge` option is applied in `emit/4` to produce a serializable signal. Two approaches:

1. **Eager merge in `emit/4`** — `emit` accepts `merge` but doesn't put the function in the signal. Instead, it sets a `merge_result` field in the signal data that `StoreArtifact` uses directly. This means the tool action applies the merge before the signal is emitted, using the current artifact state from `ctx`.
2. **Named merge strategies** — The signal carries an atom like `:append` or `{:append_max, 50}`, and `StoreArtifact` resolves it to the built-in function. Custom functions use approach 1.

Approach 1 is simpler and avoids any serialization issues. The tool action has access to current state via `ctx[:state][:artifacts]`, so it can apply the merge eagerly.

### 5.2 Schemaless Artifact Data

**Decision: Postpone.** The renderer registry already maps artifact names to renderer modules. Adding a validation layer now would be premature — with only two artifact types, the cost of maintaining schemas exceeds the benefit. Revisit when the artifact type count grows enough that malformed data becomes a real debugging problem.

### 5.3 Artifact Metadata

**Decision: Yes, add a metadata envelope around artifact data.**

Currently artifacts are stored as raw data (`"papers" => [%{id: ..., title: ...}, ...]`). This makes it impossible to know when an artifact was last updated, which agent produced it, or what version it is.

**New storage format in `agent.state.artifacts`:**

```elixir
%{
  "papers" => %{
    data: [%{id: "2301.07041", title: "...", ...}, ...],
    updated_at: ~U[2026-03-29 14:30:00Z],
    source: "/sessions/session_123",
    version: 3
  },
  "displayed_paper" => %{
    data: %{id: "2301.07041", pdf_url: "..."},
    updated_at: ~U[2026-03-29 14:31:00Z],
    source: "/sessions/session_123",
    version: 1
  }
}
```

**Impact on renderers:** All existing renderers currently access data directly (`assigns.data`). After this change, the ArtifactPanel dispatcher must unwrap: the renderer receives `artifact.data`, not the raw value. This is a one-line change in the dispatcher and is backward-compatible if done during extraction.

**Implementation in `StoreArtifact`:**

```elixir
def run(%{artifact_name: name, artifact_data: data} = params, ctx) do
  current_artifacts = get_in(ctx, [:state, :artifacts]) || %{}
  existing = Map.get(current_artifacts, name)

  # If signal carries a pre-merged result (from eager merge in emit/4), use it directly.
  # Otherwise, default merge is replace (new data replaces existing).
  merged_data =
    case params do
      %{merge_result: result} -> result
      _ -> data
    end

  updated_artifacts =
    if merged_data == nil do
      Map.delete(current_artifacts, name)
    else
      version = if existing, do: existing.version + 1, else: 1
      source = get_in(ctx, [:state, :__agent_id__]) || "unknown"

      Map.put(current_artifacts, name, %{
        data: merged_data,
        updated_at: DateTime.utc_now(),
        source: source,
        version: version
      })
    end

  {:ok, %{artifacts: updated_artifacts}}
end
```

Note: The merge function is applied eagerly in `emit/4` (see Section 5.4), not in `StoreArtifact`. This avoids serializing anonymous functions in signals. `StoreArtifact` receives the already-merged result via `:merge_result` in the signal data.

### 5.4 Using the Context Parameter in `emit/4`

**Decision: Yes, use `ctx` to populate CloudEvents fields on the signal.**

Currently `emit(_ctx, name, data, opts)` discards ctx. The action context contains `%{state: agent.state}`, where the agent state contains the agent's ID (which is the session ID in our system). This should feed into the signal's `source` and `subject` fields for proper CloudEvents compliance.

**Updated `emit/4`:**

```elixir
def emit(ctx, name, data, opts \\ []) do
  merge_fn = Keyword.get(opts, :merge)

  # Extract agent identity from action context for CloudEvents fields
  agent_id = get_in(ctx, [:state, :__agent_id__])

  # Eager merge: apply the merge function now using current artifact state.
  # This avoids serializing anonymous functions in the signal.
  signal_data =
    if merge_fn do
      existing_artifacts = get_in(ctx, [:state, :artifacts]) || %{}
      existing = get_in(existing_artifacts, [name, :data])
      merged = merge_fn.(existing, data)
      %{name: name, data: data, merge_result: merged}
    else
      %{name: name, data: data}
    end

  signal =
    Jido.Signal.new!(
      "artifact.#{name}",
      signal_data,
      source: "/jido_artifacts/#{name}",
      subject: if(agent_id, do: "/agents/#{agent_id}")
    )

  %Directive.Emit{signal: signal}
end
```

If agent identity isn't available in the context (e.g., standalone action execution outside an agent), the fields degrade gracefully to nil and the signal is still valid.

Note: The exact path to the agent ID depends on what Jido puts in the action context. If `ctx[:state][:__agent_id__]` isn't available, the agent module could set it during `on_before_cmd` or it could be threaded through the existing `runtime_context` mechanism. This needs verification against the actual Jido agent cmd flow at implementation time.

### 5.5 Shared Artifacts (Cross-Agent Scope)

**Question:** Should we build a SharedArtifact abstraction for data shared across agents, or is this too use-case-specific to abstract?

**Decision: Don't build a SharedArtifact abstraction. Instead, introduce a `scope` concept and let the persistence layer differ by scope.**

The examples of shared data are diverse:
- Task board: structured records with status lifecycle and assignment, queried/filtered by multiple agents and users
- Collaborative document: real-time co-editing, OT/CRDTs, conflict resolution
- Shared knowledge base: append-only factual store, read by all agents

These have fundamentally different requirements. A "SharedArtifact" abstraction that tries to unify them would either be so generic it's useless (just a KV store) or so constrained it blocks legitimate patterns (imposing a single persistence/querying model on all of them).

**What to do instead:** Extend the artifact signal with a `scope` field that declares where the artifact lives:

```elixir
# Agent-scoped (default, current behavior):
Artifact.emit(ctx, "papers", papers, merge: &Artifact.Merge.append/2, scope: :agent)

# Workspace-scoped (visible to all agents + user):
Artifact.emit(ctx, "task_board_summary", summary, scope: :workspace)
```

The `scope` field flows through the signal to the ArtifactPlugin. The plugin can then dispatch to different persistence backends:

| Scope | Persistence | PubSub Topic | Owner |
|-------|-------------|-------------|-------|
| `:agent` (default) | `agent.state.artifacts` via StoreArtifact (current) | `agent_artifacts:#{session_id}` | Single agent |
| `:workspace` | Consumer-provided callback or DB table (Phase 3) | `workspace_artifacts:#{workspace_id}` | Workspace |

For Phase 1 (now): Only `:agent` scope is implemented. The `scope` field exists in the signal data but `:workspace` returns an error or is ignored.

For Phase 3 (later): When shared artifacts are needed, the plugin dispatches `:workspace`-scoped artifacts to a different persistence path. The consumer provides a callback or we provide a DB-backed implementation (the workspace-scoped table from [artifact-persistence.md](artifact-persistence.md)).

This approach:
- **Doesn't over-abstract** — No generic "SharedArtifact" behaviour that tries to be all things
- **Is forward-compatible** — The scope field reserves the concept in the signal contract now
- **Leaves room for diverse implementations** — A task board can use its own Ecto table, a collab doc can use a GenServer with CRDTs, both can declare scope: :workspace
- **Doesn't confuse tool authors** — The API is the same `Artifact.emit/4` with one extra option

**Important note on tasks:** The current task system (jido_tasks) already implements its own persistence and broadcast path. That's correct — tasks have lifecycle requirements (status transitions, assignment, querying) that artifact state storage can't serve. The scope concept doesn't absorb tasks; it handles simpler shared state like "workspace summary" or "team progress dashboard."

### 5.6 Persistence Timing

**Noted but do not implement yet.** Artifacts persist at the end of the LLM turn (when `hibernate_agent/1` is called), not immediately on emit. This matches message persistence behavior and is acceptable for Phase 1. For high-value artifacts where crash-loss is impactful, the workspace-scoped DB path (Phase 3) provides immediate persistence.

### 5.7 Artifact Querying and Queryability

**Clarification:** Most artifact usage follows a "display all at once" pattern — the UI renders the current state of each artifact as a whole. This is different from tasks, which need filtering, sorting, and status queries.

This confirms that agent state is the right persistence model for artifacts. The checkpoint loads the full artifacts map on mount; the renderer displays it. No query API is needed.

The task board remains correctly separate — its querying, filtering, and status lifecycle requirements are genuinely different from the artifact pattern.

### 5.8 Summary of API Changes Before Extraction

These changes should be applied to the current jido_murmur artifact modules, then extracted as the `jido_artifacts` package:

| Change | Module | Description |
|--------|--------|-------------|
| Add metadata envelope | `StoreArtifact` | Wrap stored data in `%{data:, updated_at:, source:, version:}` |
| Use ctx in emit | `Artifact` | Populate CloudEvents `source`/`subject` from action context |
| Replace `mode` with `merge` callback | `Artifact`, `StoreArtifact` | Single `merge: fn/2` option replaces `:mode`, `:max_items`, and `:clear`. Default is replace. Built-in helpers in `Artifact.Merge` for append, bounded append, prepend, dedup. Eager merge in `emit/4` avoids serialization issues. |
| Add `:scope` field | `Artifact`, `ArtifactPlugin` | `:agent` (default) or `:workspace` (reserved for Phase 3) |
| Unwrap metadata in renderer | `ArtifactPanel` | Dispatcher passes `artifact.data` to renderers, not raw artifact |

**Updated `emit/4` signature:**

```elixir
@spec emit(map(), String.t(), term(), keyword()) :: Directive.Emit.t()
def emit(ctx, name, data, opts \\ [])

# Options:
#   :merge  - fn(existing, new) -> merged (default: replace, i.e. returns new data)
#   :scope  - :agent (default) | :workspace (reserved)
```
