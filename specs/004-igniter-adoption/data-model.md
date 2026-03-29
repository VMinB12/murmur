# Data Model: Igniter Adoption

**Feature Branch**: `004-igniter-adoption`  
**Date**: 2026-03-29

## Entities

### Install Task (Compile-time — Mix.Task module)

Represents a package's automated setup procedure.

| Field | Type | Description |
|-------|------|-------------|
| `package` | `atom()` | Package name (`:jido_murmur`, `:jido_tasks`, `:jido_murmur_web`, `:jido_artifacts`) |
| `type` | `:igniter \| :fallback` | Determined at compile time by `Code.ensure_loaded?(Igniter)` |
| `prerequisites` | `[atom()]` | Other package install tasks that must run first |

**Implementations per package**:

| Package | Task Name | Prerequisites | Actions |
|---------|-----------|---------------|---------|
| jido_murmur | `mix jido_murmur.install` | none | Generate 4 migrations, add config block, add supervisor child |
| jido_tasks | `mix jido_tasks.install` | `jido_murmur.install` | Generate 1 migration, add config block |
| jido_murmur_web | `mix jido_murmur_web.install` | none | Copy component files, inject imports |
| jido_artifacts | `mix jido_artifacts.install` | none | Add config block |

---

### Generator Task (Compile-time — Mix.Task module)

Scaffolds new modules from templates.

| Generator | Task Name | Output |
|-----------|-----------|--------|
| Agent Profile | `mix jido_murmur.gen.profile` | `lib/{app}/agents/profiles/{name}.ex` |

---

### Config Block (Runtime — application config)

Configuration entries injected by install tasks.

| Package | Config Key | Required Fields |
|---------|-----------|-----------------|
| `:jido_murmur` | `:jido_murmur` | `repo:`, `pubsub:`, `jido_mod:`, `otp_app:`, `profiles:` |
| `:jido_tasks` | `:jido_tasks` | `repo:`, `pubsub:` |
| `:jido_artifacts` | `:jido_artifacts` | `pubsub:` |

## Relationships

```
Developer
  │ runs `mix jido_tasks.install`
  ▼
jido_tasks.install
  │ checks: jido_murmur configured?
  │ NO → chains jido_murmur.install
  ▼
jido_murmur.install
  │ generates migrations
  │ adds config block
  │ adds supervisor child
  ▼
jido_tasks.install (continued)
  │ generates migration
  │ adds config block
  ▼
Igniter diff preview
  │ developer reviews
  ▼
Files written (or rejected)
```

## Validation Rules

- Install tasks MUST be idempotent — re-running produces no duplicates
- Igniter guard MUST compile cleanly when Igniter is absent
- Prerequisite check MUST detect existing configuration (not just dependency presence)
- Generated migrations MUST use unique timestamps (no collisions)
