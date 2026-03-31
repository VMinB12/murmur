# Feature Specification: Igniter Adoption

**Feature Branch**: `004-igniter-adoption`  
**Created**: 2026-03-29  
**Status**: Draft  
**Input**: Adopt Igniter as optional dependency for all packages, convert install tasks to Igniter-based tasks, add code-aware generators. Derived from architecture analysis report Section 2.

## User Scenarios & Testing

### User Story 1 - Developer Installs jido_murmur with One Command (Priority: P1)

A developer adding jido_murmur to their Phoenix application runs a single install command. The installer automatically generates required database migrations, adds configuration to `config.exs`, and adds the supervisor to their application supervision tree — with a diff preview before any changes are written.

**Why this priority**: The install experience is the first interaction developers have with the package. A smooth, automated setup reduces friction and support burden. This is the highest-value Igniter use case.

**Independent Test**: Can be tested by running the install command against a fresh Phoenix project scaffold and verifying all expected files are created/modified.

**Acceptance Scenarios**:

1. **Given** a fresh Phoenix application with `{:jido_murmur, "~> 0.1"}` in deps, **When** the developer runs the install command, **Then** database migration files are generated in `priv/repo/migrations/`
2. **Given** a fresh Phoenix application, **When** the install completes, **Then** `config.exs` contains a `:jido_murmur` configuration block with `repo`, `pubsub`, `jido_mod`, and `otp_app` keys
3. **Given** a fresh Phoenix application, **When** the install completes, **Then** the application's supervision tree includes the jido_murmur supervisor
4. **Given** a Phoenix application that already has jido_murmur installed, **When** the developer re-runs the install command, **Then** no duplicate configurations or migrations are created (idempotent)
5. **Given** a developer running the install, **When** changes are proposed, **Then** a diff preview is shown and the developer can accept or reject changes before they are written

---

### User Story 2 - Developer Installs jido_tasks with Dependency Chain (Priority: P1)

A developer installs jido_tasks, which requires jido_murmur's database tables (foreign key dependency). The installer detects whether jido_murmur is already installed and chains the prerequisite install if needed.

**Why this priority**: jido_tasks depends on jido_murmur's database schema. Without automatic chaining, developers hit foreign key errors that are confusing to debug.

**Independent Test**: Can be tested by running the jido_tasks install against a fresh project (without jido_murmur installed) and verifying both packages get set up.

**Acceptance Scenarios**:

1. **Given** a project without jido_murmur configured, **When** the developer runs the jido_tasks install, **Then** jido_murmur's install runs first, followed by jido_tasks' own setup
2. **Given** a project with jido_murmur already installed, **When** the developer runs the jido_tasks install, **Then** only jido_tasks' setup runs (no duplicate jido_murmur setup)
3. **Given** a successful jido_tasks install, **Then** `config.exs` contains both `:jido_murmur` and `:jido_tasks` configuration blocks

---

### User Story 3 - Developer Installs jido_murmur_web Components (Priority: P2)

A developer installing jido_murmur_web runs the install command to copy UI component files into their project and optionally inject imports into their application's shared helpers.

**Why this priority**: Component installation is useful but less critical than database/config setup since components can be manually copied. Automating it improves DX but isn't a blocker.

**Independent Test**: Can be tested by running the install against a Phoenix project and verifying component files are created and imports are injected.

**Acceptance Scenarios**:

1. **Given** a Phoenix application with jido_murmur_web added, **When** the developer runs the install, **Then** component files are copied to the appropriate directory in their project
2. **Given** the install completes, **Then** the application's shared HTML helpers module includes the appropriate import for the installed components

---

### User Story 4 - Developer Uses Igniter-Free Fallback (Priority: P2)

A developer who hasn't added Igniter to their project attempts to run an install task. Instead of crashing with a compilation error, they receive a clear message explaining that Igniter is required for automated setup, with instructions on how to add it or perform manual setup.

**Why this priority**: The guard pattern must work correctly — Igniter is optional, so the package must degrade gracefully. This is core to the "zero-risk" promise.

**Independent Test**: Can be tested by removing Igniter from deps and running the install command.

**Acceptance Scenarios**:

1. **Given** a project without Igniter in its dependencies, **When** the developer runs the install command, **Then** they receive a clear error message explaining Igniter is needed
2. **Given** the error message, **Then** it includes instructions for adding Igniter to deps or a link to manual setup documentation

---

### User Story 5 - Developer Scaffolds Agent Profile (Priority: P3)

A developer uses a generator command to scaffold a new agent profile module with pre-configured tools and plugins. The generator creates a well-structured module following project conventions.

**Why this priority**: Additive DX improvement. Developers can create profiles manually. This saves time but isn't essential for package adoption.

**Independent Test**: Can be tested by running the generator and verifying the output module compiles and follows the expected structure.

**Acceptance Scenarios**:

1. **Given** a project with jido_murmur installed, **When** the developer runs the profile generator with a name, **Then** a new module file is created with the appropriate structure (name, description, system_prompt, tools, plugins)
2. **Given** the generated profile, **When** it is compiled, **Then** it compiles without errors and can be used to configure an agent

---

### Edge Cases

- What happens when a developer runs install on a non-Phoenix project (e.g., a plain Mix project)? The installer should detect the absence of Phoenix and either skip Phoenix-specific steps or provide a clear message.
- What happens when the developer's `config.exs` has an unusual structure (e.g., custom formatting, conditional blocks)? Igniter's AST-aware approach handles this better than template-based generation.
- What happens when migration timestamps conflict with existing migrations? The migration generator should use timestamps that don't collide.

## Requirements

### Functional Requirements

- **FR-001**: All packages (jido_murmur, jido_tasks, jido_murmur_web, jido_artifacts) MUST declare Igniter as an optional dependency
- **FR-002**: Each package MUST use the guard pattern (`if Code.ensure_loaded?(Igniter)`) to provide both Igniter-based and fallback task implementations
- **FR-003**: The jido_murmur install task MUST generate database migrations, add configuration to `config.exs`, and add the supervisor to the application supervision tree
- **FR-004**: The jido_tasks install task MUST chain jido_murmur's install as a prerequisite when not already configured
- **FR-005**: The jido_murmur_web install task MUST copy component files and inject imports into the application's HTML helpers
- **FR-006**: All install tasks MUST be idempotent — re-running MUST NOT create duplicate configurations, migrations, or supervisor entries
- **FR-007**: All install tasks MUST show a diff preview before writing changes
- **FR-008**: The fallback (non-Igniter) task MUST display a clear error message with remediation instructions
- **FR-009**: The profile generator MUST create a module file following project conventions for agent profiles

### Key Entities

- **Install Task**: A Mix task that automates package setup in a consumer application. Either Igniter-based (AST-aware, with diff preview) or fallback (error message).
- **Generator Task**: A Mix task that scaffolds new modules (profiles, renderers) following project conventions.
- **Guard Pattern**: The `if Code.ensure_loaded?(Igniter)` conditional that selects between Igniter and fallback implementations at compile time.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A new developer can set up jido_murmur in a Phoenix project by running a single install command — no manual config.exs editing required
- **SC-002**: Install tasks are idempotent — running them twice produces no duplicate artifacts
- **SC-003**: All packages compile and function correctly when Igniter is not present in the consumer's dependencies
- **SC-004**: The install experience matches the Jido ecosystem standard (same DX as `mix igniter.install jido`)
- **SC-005**: Generated modules compile without errors and follow established project conventions

## Assumptions

- Igniter version ~> 0.7 is stable and compatible with our dependency tree.
- The Jido guard pattern (`Code.ensure_loaded?(Igniter)`) is the established convention and works reliably across Elixir versions.
- Phoenix applications follow standard file structure conventions (config/config.exs, lib/my_app/application.ex, etc.) that Igniter can navigate.
- No packages have been published to Hex yet, so adopting Igniter involves zero breaking changes for external consumers.
- Developers are familiar with the `mix igniter.install` workflow from Jido core packages.
