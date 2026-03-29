# Research: Igniter Adoption

**Feature Branch**: `004-igniter-adoption`  
**Date**: 2026-03-29

## Research Tasks

### R1: Current Install Task Architecture

**Context**: Need to understand existing install tasks to plan the Igniter migration.

**Finding**: Three install tasks exist as standard `Mix.Task` modules:
- `Mix.Tasks.JidoMurmur.Install` — generates 4 Ecto migrations via EEx templates
- `Mix.Tasks.JidoMurmurWeb.Install` — copies component source files into consumer project
- `Mix.Tasks.JidoTasks.Install` — generates jido_tasks migration

None use Igniter. All use `Mix.Generator` for file creation. No idempotency checks, no diff preview.

**Decision**: Convert all three to Igniter-based tasks using the guard pattern. Keep existing logic as reference but rewrite using Igniter's AST-aware APIs for config injection and supervision tree modification.

**Rationale**: Igniter provides AST-aware code modification, diff preview, and idempotency — all requirements from the spec.

### R2: Igniter Guard Pattern Best Practices

**Context**: Igniter must be optional. Need a compile-safe guard.

**Finding**: The Jido ecosystem uses `Code.ensure_loaded?(Igniter)` as a compile-time guard. When the guard fails, the module body defines a fallback task that prints an error message.

**Decision**: Use the established pattern:
```elixir
if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.MyPackage.Install do
    use Igniter
    # ... Igniter-based implementation
  end
else
  defmodule Mix.Tasks.MyPackage.Install do
    use Mix.Task
    def run(_args) do
      Mix.shell().error("...")
    end
  end
end
```

**Rationale**: This is the established convention in the Jido ecosystem and avoids compilation errors when Igniter is absent.

**Alternatives Considered**:
- Runtime check with `Application.ensure_all_started(:igniter)` → rejected because it causes compilation errors if Igniter modules are referenced
- Separate task modules (e.g., `Install` and `Install.Igniter`) → rejected because it creates confusing UX with two different task names

### R3: Igniter Version Compatibility

**Context**: Need to verify Igniter ~> 0.7 compatibility with our dependency tree.

**Finding**: Igniter 0.7+ requires Elixir >= 1.15 (we have >= 1.15) and has no conflicting dependencies with our stack. It's already used by the Jido core package for its own install tasks.

**Decision**: Declare `{:igniter, "~> 0.7", optional: true, runtime: false}` in each package's mix.exs.

**Rationale**: `optional: true` means consumers aren't forced to include it. `runtime: false` means it's only needed at compile/dev time for running install tasks.

### R4: Install Task Dependency Chaining

**Context**: jido_tasks depends on jido_murmur's database tables. The installer needs to chain prerequisites.

**Finding**: Igniter supports composing install tasks via `Igniter.compose_task/3`. This allows one installer to invoke another.

**Decision**: In `jido_tasks.install`, check if jido_murmur is configured (look for `:jido_murmur` config key). If not, compose `jido_murmur.install` first. This ensures migrations run in the correct order.

**Rationale**: Automatic chaining prevents foreign key errors from missing prerequisite tables.

### R5: Config Injection Points

**Context**: Need to identify what config the installer must add.

**Finding**: Required config keys per package:
- `:jido_murmur` → `repo:`, `pubsub:`, `jido_mod:`, `otp_app:`, `profiles:`, `authorize:`
- `:jido_tasks` → `repo:`, `pubsub:`
- `:jido_artifacts` → `pubsub:`

**Decision**: Igniter install tasks will:
1. Add config blocks to `config/config.exs`
2. Add supervisor child to `application.ex` (jido_murmur only)
3. Generate migrations
4. All changes shown in diff preview before write

**Rationale**: Covers the complete setup path. Diff preview lets developers review before committing.

### R6: Generator Patterns for Agent Profiles

**Context**: Spec mentions scaffolding agent profiles.

**Finding**: Agent profiles follow a consistent pattern:
```elixir
use Jido.AI.Agent,
  name: "...",
  description: "...",
  model: :fast,
  tools: [...],
  plugins: [StreamingPlugin, ArtifactPlugin],
  system_prompt: "..."
```

**Decision**: Create `mix jido_murmur.gen.profile` generator that creates a new profile module with default tools, plugins, and a placeholder system prompt. EEx template with configurable name.

**Rationale**: Reduces boilerplate for new agents. Standard generator pattern familiar to Phoenix developers.
