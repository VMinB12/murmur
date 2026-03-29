# Tasks: Modular Hex Package Extraction

**Input**: Design documents from `/specs/002-modular-hex-extraction/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/public-api.md, contracts/pubsub.md, quickstart.md

**Tests**: Included — FR-019 requires per-package test suites; FR-024 requires 80% line coverage per package.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Umbrella root**: `mix.exs`, `config/`
- **Core package**: `apps/jido_murmur/lib/jido_murmur/`
- **Web package**: `apps/jido_murmur_web/lib/jido_murmur_web/`
- **Tasks package**: `apps/jido_tasks/lib/jido_tasks/`
- **Arxiv package**: `apps/jido_arxiv/lib/jido_arxiv/`
- **Demo app**: `apps/murmur_demo/lib/murmur/` and `apps/murmur_demo/lib/murmur_web/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Convert existing project to Mix umbrella and create package skeletons

- [x] T001 Create umbrella root mix.exs with apps_path and shared deps at mix.exs
- [x] T002 Create apps/ directory and jido_murmur package skeleton with mix.exs, lib/, test/ at apps/jido_murmur/
- [x] T003 [P] Create jido_murmur_web package skeleton with mix.exs, lib/, test/ at apps/jido_murmur_web/
- [x] T004 [P] Create jido_tasks package skeleton with mix.exs, lib/, test/ at apps/jido_tasks/
- [x] T005 [P] Create jido_arxiv package skeleton with mix.exs, lib/, test/ at apps/jido_arxiv/
- [x] T006 [P] Create murmur_demo app skeleton with mix.exs at apps/murmur_demo/
- [x] T007 Configure umbrella shared config files (config.exs, dev.exs, test.exs, prod.exs, runtime.exs) in config/
- [x] T008 Run mix deps.get from umbrella root and verify all packages compile

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented — config system, Ecto schemas, ETS tables, storage adapter, supervision tree, LLM behaviour, and test infrastructure.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T009 Implement JidoMurmur root config module with repo/pubsub/jido_mod/otp_app accessors at apps/jido_murmur/lib/jido_murmur.ex
- [x] T010 [P] Extract and rename Workspace schema (Murmur.Workspaces.Workspace → JidoMurmur.Workspaces.Workspace) with owner_id and metadata fields at apps/jido_murmur/lib/jido_murmur/workspaces/workspace.ex
- [x] T011 [P] Extract and rename AgentSession schema (Murmur.Workspaces.AgentSession → JidoMurmur.Workspaces.AgentSession) with owner_id, metadata fields, and removed max-agents constraint at apps/jido_murmur/lib/jido_murmur/workspaces/agent_session.ex
- [x] T012 [P] Extract and rename Checkpoint schema (Murmur.Storage.Checkpoint → JidoMurmur.Storage.Checkpoint) at apps/jido_murmur/lib/jido_murmur/storage/checkpoint.ex
- [x] T013 [P] Extract and rename ThreadEntry schema (Murmur.Storage.ThreadEntry → JidoMurmur.Storage.ThreadEntry) at apps/jido_murmur/lib/jido_murmur/storage/thread_entry.ex
- [x] T014 Create migration templates for all 4 tables (jido_murmur_workspaces, jido_murmur_agent_sessions, jido_murmur_checkpoints, jido_murmur_thread_entries) at apps/jido_murmur/priv/templates/
- [x] T015 Implement Mix.Tasks.JidoMurmur.Install migration generator with duplicate detection at apps/jido_murmur/lib/mix/tasks/jido_murmur.install.ex
- [x] T016 Extract and rename TableOwner GenServer (Murmur.Agents.TableOwner → JidoMurmur.TableOwner) with jido_murmur_ ETS name prefixes at apps/jido_murmur/lib/jido_murmur/table_owner.ex
- [x] T017 [P] Extract and rename PendingQueue (Murmur.Agents.PendingQueue → JidoMurmur.PendingQueue) with namespaced ETS table references at apps/jido_murmur/lib/jido_murmur/pending_queue.ex
- [x] T018 Extract and rename Storage.Ecto adapter (Murmur.Storage.Ecto → JidoMurmur.Storage.Ecto) using JidoMurmur.repo() config at apps/jido_murmur/lib/jido_murmur/storage/ecto.ex
- [x] T019 Implement JidoMurmur.Supervisor managing TableOwner at apps/jido_murmur/lib/jido_murmur/supervisor.ex
- [x] T020 [P] Define LLM behaviour with ask/4 and await/3 callbacks at apps/jido_murmur/lib/jido_murmur/llm.ex
- [x] T021 [P] Extract LLM.Real production adapter (Murmur.Agents.LLM.Real → JidoMurmur.LLM.Real) at apps/jido_murmur/lib/jido_murmur/llm/real.ex
- [x] T022 [P] Create LLM.Mock test adapter with configurable canned responses at apps/jido_murmur/lib/jido_murmur/llm/mock.ex
- [x] T023 Extract and rename Workspaces context (Murmur.Workspaces → JidoMurmur.Workspaces) with pluggable authorization hook at apps/jido_murmur/lib/jido_murmur/workspaces.ex
- [x] T024 Create per-package test infrastructure: test_helper.exs and JidoMurmur.Case module with Ecto sandbox at apps/jido_murmur/test/support/case.ex

**Checkpoint**: Foundation ready — user story implementation can now begin

---

## Phase 3: User Story 1 — Consumer Bootstraps Multi-Agent App (Priority: P1) 🎯 MVP

**Goal**: A consumer adds jido_murmur, runs the install generator, configures Repo/PubSub/Jido, defines agent profiles, and gets working multi-agent orchestration with streaming, persistence, and inter-agent messaging.

**Independent Test**: Create a test agent with StreamingPlugin and TellAction, send a message through Runner, verify streaming signals on PubSub and message persistence in Storage.Ecto.

### Implementation for User Story 1

- [x] T025 [US1] Extract Runner (Murmur.Agents.Runner → JidoMurmur.Runner) with JidoMurmur config references at apps/jido_murmur/lib/jido_murmur/runner.ex
- [x] T026 [P] [US1] Extract and refactor Catalog (Murmur.Agents.Catalog → JidoMurmur.Catalog) to config-driven profile registry at apps/jido_murmur/lib/jido_murmur/catalog.ex
- [x] T027 [P] [US1] Extract UITurn (Murmur.Agents.UITurn → JidoMurmur.UITurn) at apps/jido_murmur/lib/jido_murmur/ui_turn.ex
- [x] T028 [P] [US1] Extract StreamingPlugin (Murmur.Agents.StreamingPlugin → JidoMurmur.StreamingPlugin) with JidoMurmur.pubsub() at apps/jido_murmur/lib/jido_murmur/streaming_plugin.ex
- [x] T029 [P] [US1] Extract ArtifactPlugin (Murmur.Agents.ArtifactPlugin → JidoMurmur.ArtifactPlugin) at apps/jido_murmur/lib/jido_murmur/artifact_plugin.ex
- [x] T030 [P] [US1] Extract Artifact helpers (Murmur.Agents.Artifact → JidoMurmur.Artifact) at apps/jido_murmur/lib/jido_murmur/artifact.ex
- [x] T031 [P] [US1] Extract TellAction (Murmur.Agents.TellAction → JidoMurmur.TellAction) at apps/jido_murmur/lib/jido_murmur/tell_action.ex
- [x] T032 [P] [US1] Extract StoreArtifact (Murmur.Agents.Actions.StoreArtifact → JidoMurmur.Actions.StoreArtifact) at apps/jido_murmur/lib/jido_murmur/actions/store_artifact.ex
- [x] T033 [P] [US1] Extract MessageInjector (Murmur.Agents.MessageInjector → JidoMurmur.MessageInjector) at apps/jido_murmur/lib/jido_murmur/message_injector.ex
- [x] T034 [P] [US1] Extract TeamInstructions (Murmur.Agents.TeamInstructions → JidoMurmur.TeamInstructions) at apps/jido_murmur/lib/jido_murmur/team_instructions.ex
- [x] T035 [US1] Create AgentHelper convenience module (start_agent, load_messages, load_artifacts, subscribe, cleanup) at apps/jido_murmur/lib/jido_murmur/agent_helper.ex
- [x] T036 [US1] Add :telemetry events to Runner (send_message start/stop/exception), agent start/stop, streaming signal, and artifact store at apps/jido_murmur/lib/jido_murmur/runner.ex and plugin modules

### Tests for User Story 1

- [x] T037 [P] [US1] Write unit tests for Runner send_message and drain-loop at apps/jido_murmur/test/jido_murmur/runner_test.exs
- [x] T038 [P] [US1] Write unit tests for config-driven Catalog at apps/jido_murmur/test/jido_murmur/catalog_test.exs
- [x] T039 [P] [US1] Write unit tests for Storage.Ecto (checkpoint and thread CRUD) at apps/jido_murmur/test/jido_murmur/storage/ecto_test.exs
- [x] T040 [P] [US1] Write unit tests for Workspaces context (workspace + session CRUD, auth hook) at apps/jido_murmur/test/jido_murmur/workspaces_test.exs
- [x] T041 [P] [US1] Write unit tests for PendingQueue (enqueue, drain, concurrent access) at apps/jido_murmur/test/jido_murmur/pending_queue_test.exs
- [x] T042 [P] [US1] Write unit tests for UITurn projection at apps/jido_murmur/test/jido_murmur/ui_turn_test.exs
- [x] T043 [P] [US1] Write unit tests for AgentHelper at apps/jido_murmur/test/jido_murmur/agent_helper_test.exs
- [x] T044 [US1] Write integration test for end-to-end message flow (send → Runner → LLM → streaming → persistence) at apps/jido_murmur/test/jido_murmur/integration/message_flow_test.exs

**Checkpoint**: jido_murmur core package is functional — a consumer can install, configure, define agents, and run multi-agent orchestration

---

## Phase 4: User Story 2 — Consumer Uses Jido Directly Alongside jido_murmur (Priority: P1)

**Goal**: A Jido-experienced developer uses package plugins/helpers for common operations while calling Jido APIs directly for advanced features, with no interference between custom and package components.

**Independent Test**: Add a custom Jido.Plugin alongside package plugins, call Jido.AgentServer.state/1 directly, and verify both work without conflicts.

### Implementation for User Story 2

- [x] T045 [US2] Verify all public APIs return native Jido types (pids, Signal structs, Thread entries) — audit and fix any wrapping at apps/jido_murmur/lib/jido_murmur/agent_helper.ex and apps/jido_murmur/lib/jido_murmur/runner.ex

### Tests for User Story 2

- [x] T046 [P] [US2] Write test for custom Jido.Plugin executing alongside StreamingPlugin and ArtifactPlugin at apps/jido_murmur/test/jido_murmur/integration/jido_interplay_test.exs
- [x] T047 [P] [US2] Write test for direct Jido.AgentServer.state/1 access on agent started via AgentHelper at apps/jido_murmur/test/jido_murmur/integration/jido_interplay_test.exs
- [x] T048 [US2] Write test for alternative Jido.Storage implementation working with Runner at apps/jido_murmur/test/jido_murmur/integration/jido_interplay_test.exs
- [x] T049 [US2] Document Jido interplay patterns and examples in apps/jido_murmur/README.md

**Checkpoint**: Jido-native design is validated — custom and package Jido components compose seamlessly

---

## Phase 5: User Story 3 — Consumer Adds UI with jido_murmur_web Components (Priority: P2)

**Goal**: A developer adds jido_murmur_web for pre-built LiveView chat components, with both direct-import and generator-based installation modes.

**Independent Test**: Import ChatMessage and StreamingIndicator into a test LiveView, render messages, verify streaming state display. Run generator and confirm files copied correctly.

### Implementation for User Story 3

- [x] T050 [P] [US3] Extract ChatMessage function component to apps/jido_murmur_web/lib/jido_murmur_web/components/chat_message.ex
- [x] T051 [P] [US3] Extract ChatStream function component to apps/jido_murmur_web/lib/jido_murmur_web/components/chat_stream.ex
- [x] T052 [P] [US3] Extract AgentHeader function component to apps/jido_murmur_web/lib/jido_murmur_web/components/agent_header.ex
- [x] T053 [P] [US3] Extract MessageInput function component to apps/jido_murmur_web/lib/jido_murmur_web/components/message_input.ex
- [x] T054 [P] [US3] Extract StreamingIndicator function component to apps/jido_murmur_web/lib/jido_murmur_web/components/streaming_indicator.ex
- [x] T055 [P] [US3] Extract AgentSelector function component to apps/jido_murmur_web/lib/jido_murmur_web/components/agent_selector.ex
- [x] T056 [P] [US3] Extract WorkspaceList function component to apps/jido_murmur_web/lib/jido_murmur_web/components/workspace_list.ex
- [x] T057 [P] [US3] Extract ArtifactPanel function component with configurable renderer registry at apps/jido_murmur_web/lib/jido_murmur_web/components/artifact_panel.ex
- [x] T058 [US3] Create unified Components import module at apps/jido_murmur_web/lib/jido_murmur_web/components.ex
- [x] T059 [US3] Copy component source files as EEx templates for generator at apps/jido_murmur_web/priv/templates/components/
- [x] T060 [US3] Implement Mix.Tasks.JidoMurmurWeb.Install generator with component group selection (chat, workspace, artifacts, all) at apps/jido_murmur_web/lib/mix/tasks/jido_murmur_web.install.ex

### Tests for User Story 3

- [x] T061 [P] [US3] Write component render tests for ChatMessage, ChatStream, MessageInput at apps/jido_murmur_web/test/jido_murmur_web/components/chat_test.exs
- [x] T062 [P] [US3] Write component render tests for StreamingIndicator, AgentHeader, AgentSelector at apps/jido_murmur_web/test/jido_murmur_web/components/agent_test.exs
- [x] T063 [P] [US3] Write component render test for ArtifactPanel with renderer dispatch at apps/jido_murmur_web/test/jido_murmur_web/components/artifact_panel_test.exs
- [x] T064 [US3] Write generator test verifying file copy and namespace substitution at apps/jido_murmur_web/test/mix/tasks/install_test.exs

**Checkpoint**: jido_murmur_web delivers reusable LiveView components via both direct import and generator installation

---

## Phase 6: User Story 4 — Consumer Adds Domain-Specific Tools from Plugin Packages (Priority: P2)

**Goal**: A developer adds jido_tasks and jido_arxiv to give agents task management and academic research capabilities via standard Jido.Action composition.

**Independent Test**: Add AddTask/ListTasks tools to a test agent's tools list, run the migration generator, send a task creation request, verify the task is persisted and listed.

### Implementation for User Story 4 — jido_tasks

- [x] T065 [US4] Implement JidoTasks root config module with repo/pubsub accessors at apps/jido_tasks/lib/jido_tasks.ex
- [x] T066 [P] [US4] Extract Task schema (Murmur.Tasks.Task → JidoTasks.Task) with owner_id, metadata fields at apps/jido_tasks/lib/jido_tasks/task.ex
- [x] T067 [US4] Extract Tasks context (Murmur.Tasks → JidoTasks.Tasks) with CRUD, stats, PubSub broadcasts at apps/jido_tasks/lib/jido_tasks/tasks.ex
- [x] T068 [P] [US4] Extract AddTask tool (Murmur.Agents.Tools.AddTask → JidoTasks.Tools.AddTask) at apps/jido_tasks/lib/jido_tasks/tools/add_task.ex
- [x] T069 [P] [US4] Extract UpdateTask tool (Murmur.Agents.Tools.UpdateTask → JidoTasks.Tools.UpdateTask) at apps/jido_tasks/lib/jido_tasks/tools/update_task.ex
- [x] T070 [P] [US4] Extract ListTasks tool (Murmur.Agents.Tools.ListTasks → JidoTasks.Tools.ListTasks) at apps/jido_tasks/lib/jido_tasks/tools/list_tasks.ex
- [x] T071 [US4] Create migration template and Mix.Tasks.JidoTasks.Install generator with jido_murmur_workspaces FK check at apps/jido_tasks/lib/mix/tasks/jido_tasks.install.ex
- [x] T072 [US4] Create test infrastructure (test_helper.exs, JidoTasks.Case with sandbox) at apps/jido_tasks/test/support/case.ex

### Implementation for User Story 4 — jido_arxiv

- [x] T073 [US4] Implement JidoArxiv root module at apps/jido_arxiv/lib/jido_arxiv.ex
- [x] T074 [P] [US4] Extract ArxivSearch tool (Murmur.Agents.Tools.ArxivSearch → JidoArxiv.Tools.ArxivSearch) at apps/jido_arxiv/lib/jido_arxiv/tools/arxiv_search.ex
- [x] T075 [P] [US4] Extract DisplayPaper tool (Murmur.Agents.Tools.DisplayPaper → JidoArxiv.Tools.DisplayPaper) at apps/jido_arxiv/lib/jido_arxiv/tools/display_paper.ex

### Tests for User Story 4

- [x] T076 [P] [US4] Write unit tests for Tasks context (create, update, list, stats, PubSub) at apps/jido_tasks/test/jido_tasks/tasks_test.exs
- [x] T077 [P] [US4] Write unit tests for AddTask, UpdateTask, ListTasks tools at apps/jido_tasks/test/jido_tasks/tools/tool_test.exs
- [x] T078 [P] [US4] Write unit tests for ArxivSearch and DisplayPaper tools at apps/jido_arxiv/test/jido_arxiv/tools/tool_test.exs
- [x] T079 [US4] Write integration test for agent with tools from multiple packages (jido_murmur + jido_tasks + jido_arxiv) at apps/jido_tasks/test/jido_tasks/integration/multi_package_test.exs

**Checkpoint**: Plugin packages deliver domain-specific Jido.Action tools that compose via standard Jido mechanisms

---

## Phase 7: User Story 5 — Consumer Composes Multiple Request Transformers (Priority: P3)

**Goal**: A developer chains MessageInjector with a custom request transformer via ComposableRequestTransformer, enabling extensible request processing without upstream Jido changes.

**Independent Test**: Define two transformers, compose them, process a request, verify both transformers' modifications appear in sequence with correct deep-merge behaviour.

### Implementation for User Story 5

- [x] T080 [US5] Implement ComposableRequestTransformer with sequential chain and deep-merge at apps/jido_murmur/lib/jido_murmur/composable_request_transformer.ex

### Tests for User Story 5

- [x] T081 [P] [US5] Write unit tests for ComposableRequestTransformer (chain execution, deep-merge, error propagation) at apps/jido_murmur/test/jido_murmur/composable_request_transformer_test.exs
- [x] T082 [US5] Write integration test composing MessageInjector with a custom transformer at apps/jido_murmur/test/jido_murmur/integration/composable_transformer_test.exs

**Checkpoint**: Multi-transformer composition works, enabling extensible request processing

---

## Phase 8: User Story 6 — Existing Murmur Demo App Runs on Umbrella Packages (Priority: P1)

**Goal**: The current Murmur application is relocated to murmur_demo within the umbrella, depending on all extracted packages via in_umbrella references. All existing features and tests work unchanged.

**Independent Test**: Run `mix test` from umbrella root — all 29 existing test modules must pass. Start dev server and verify workspace creation, multi-agent chat, artifact rendering, and task management.

### Implementation for User Story 6

- [X] T083 [US6] Move Murmur.Application to apps/murmur_demo/lib/murmur/application.ex and add JidoMurmur.Supervisor to children
- [X] T084 [P] [US6] Move Murmur.Repo to apps/murmur_demo/lib/murmur/repo.ex
- [X] T085 [P] [US6] Move Murmur.Jido to apps/murmur_demo/lib/murmur/jido.ex with JidoMurmur.Storage.Ecto config
- [X] T086 [P] [US6] Move agent profiles (GeneralAgent, ArxivAgent) to apps/murmur_demo/lib/murmur/agents/profiles/
- [X] T087 [US6] Move MurmurWeb module and helpers to apps/murmur_demo/lib/murmur_web.ex
- [X] T088 [P] [US6] Move web infrastructure (endpoint, router, telemetry) to apps/murmur_demo/lib/murmur_web/
- [X] T089 [US6] Move LiveViews (WorkspaceLive, WorkspaceListLive) to apps/murmur_demo/lib/murmur_web/live/ and update references from Murmur.Agents.* to JidoMurmur.*
- [X] T090 [US6] Move web components (core_components.ex, layouts.ex, artifacts.ex) to apps/murmur_demo/lib/murmur_web/components/
- [X] T091 [US6] Move assets (JS, CSS, vendor) to apps/murmur_demo/assets/
- [X] T092 [US6] Move priv/ (static files, gettext, existing migrations) to apps/murmur_demo/priv/
- [X] T093 [US6] Update murmur_demo config to reference JidoMurmur, JidoTasks, JidoArxiv packages
- [X] T094 [US6] Update all module references throughout demo app (Murmur.Agents.Runner → JidoMurmur.Runner, Murmur.Agents.Catalog → JidoMurmur.Catalog, Murmur.Storage.* → JidoMurmur.Storage.*, Murmur.Tasks.* → JidoTasks.*, etc.)
- [X] T095 [US6] Migrate existing tests to apps/murmur_demo/test/ with updated module references
- [X] T096 [US6] Remove old top-level lib/ and test/ directories after migration is verified
- [X] T097 [US6] Run full test suite from umbrella root and verify all existing tests pass

**Checkpoint**: Demo app runs identically to pre-extraction Murmur — all features and tests operational

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Quality gates, documentation, and publishing readiness

- [x] T098 [P] Configure per-package coverage reporting and verify 80% line coverage per package
- [x] T099 [P] Write README.md for jido_murmur at apps/jido_murmur/README.md
- [x] T100 [P] Write README.md for jido_murmur_web at apps/jido_murmur_web/README.md
- [x] T101 [P] Write README.md for jido_tasks at apps/jido_tasks/README.md
- [x] T102 [P] Write README.md for jido_arxiv at apps/jido_arxiv/README.md
- [x] T103 Update umbrella root README.md with project overview and architecture diagram
- [x] T104 [P] Add Hex publishing metadata (description, licenses, links, source_url) to each package mix.exs
- [x] T105 Run quickstart.md validation — simulate consumer integration steps against the packages
- [x] T106 Run mix precommit from umbrella root and fix any remaining issues

---

## Phase 10: Coverage, Testing Hygiene & Hex Readiness

**Purpose**: Reach 80% coverage threshold per package, fix test infrastructure warnings, configure security scanning, and prepare in_umbrella deps for Hex publishing.

**Dependencies**: Phase 9 complete

### Coverage — jido_murmur (66% → 80%)

- [ ] T107 [P] Write unit tests for JidoMurmur.TellAction (send to existing/missing agent, queuing) at apps/jido_murmur/test/jido_murmur/tell_action_test.exs
- [ ] T108 [P] Write unit tests for JidoMurmur.ArtifactPlugin (signal handling, artifact extraction) at apps/jido_murmur/test/jido_murmur/artifact_plugin_test.exs
- [ ] T109 [P] Write unit tests for JidoMurmur.Actions.StoreArtifact (store/retrieve artifact state) at apps/jido_murmur/test/jido_murmur/actions/store_artifact_test.exs
- [ ] T110 [P] Write unit tests for JidoMurmur.Supervisor (child spec, start_link) at apps/jido_murmur/test/jido_murmur/supervisor_test.exs
- [ ] T111 [P] Write unit tests for JidoMurmur.TableOwner (ETS table creation, ownership transfer) at apps/jido_murmur/test/jido_murmur/table_owner_test.exs
- [ ] T112 [P] Write unit tests for JidoMurmur.Artifact (helper functions, signal construction) at apps/jido_murmur/test/jido_murmur/artifact_test.exs
- [ ] T113 [P] Write unit tests for JidoMurmur.StreamingPlugin (signal dispatch to PubSub) at apps/jido_murmur/test/jido_murmur/streaming_plugin_test.exs
- [ ] T114 [P] Write unit test for Mix.Tasks.JidoMurmur.Install (migration file generation, duplicate detection) at apps/jido_murmur/test/mix/tasks/jido_murmur_install_test.exs

### Coverage — jido_murmur_web (88% → 80%)

- [ ] T115 [P] Write render test for JidoMurmurWeb.Components.WorkspaceList at apps/jido_murmur_web/test/jido_murmur_web/components/workspace_list_test.exs

### Coverage — jido_tasks (66% → 80%)

- [ ] T116 [P] Write unit tests for JidoTasks.Tools.AddTask (param validation, task creation) at apps/jido_tasks/test/jido_tasks/tools/add_task_test.exs
- [ ] T117 [P] Write unit tests for JidoTasks.Tools.UpdateTask (status transitions, error cases) at apps/jido_tasks/test/jido_tasks/tools/update_task_test.exs
- [ ] T118 [P] Write unit test for Mix.Tasks.JidoTasks.Install (migration generation, FK check) at apps/jido_tasks/test/mix/tasks/jido_tasks_install_test.exs

### Coverage — jido_arxiv (28% → 80%)

- [ ] T119 Write unit tests for JidoArxiv.Tools.ArxivSearch with mocked HTTP (Req.Test or similar) at apps/jido_arxiv/test/jido_arxiv/tools/arxiv_search_test.exs

### Test Infrastructure Hygiene

- [ ] T120 Fix Mox mock redefine warning — murmur_demo Mox.defmock(JidoMurmur.LLM.Mock) conflicts with lib module; either remove lib/jido_murmur/llm/mock.ex and use Mox exclusively, or remove Mox.defmock in murmur_demo and use the lib module directly at apps/jido_murmur/lib/jido_murmur/llm/mock.ex and apps/murmur_demo/test/test_helper.exs

### Security Scanning

- [ ] T121 Configure sobelow for umbrella — add per-app .sobelow-conf for murmur_demo (Phoenix app) and update umbrella precommit alias to run sobelow against apps/murmur_demo at .sobelow-conf and apps/murmur_demo/.sobelow-conf and mix.exs

### Hex Publishing Readiness

- [ ] T122 [P] Add conditional deps to jido_murmur_web mix.exs — replace in_umbrella with version-pinned dep when HEX_PUBLISH env is set at apps/jido_murmur_web/mix.exs
- [ ] T123 [P] Add conditional deps to jido_tasks mix.exs — replace in_umbrella with version-pinned dep when HEX_PUBLISH env is set at apps/jido_tasks/mix.exs
- [ ] T124 [P] Add conditional deps to jido_arxiv mix.exs — replace in_umbrella with version-pinned dep when HEX_PUBLISH env is set at apps/jido_arxiv/mix.exs
- [ ] T125 Verify hex.build for each package produces valid tarball (mix hex.build --unpack in tmp dir) for apps/jido_murmur, apps/jido_murmur_web, apps/jido_tasks, apps/jido_arxiv

### Final Gate

- [ ] T126 Run mix test --cover per package and verify all 4 library packages meet 80% threshold
- [ ] T127 Run mix precommit from umbrella root and fix any remaining issues

**Checkpoint**: All packages meet coverage gate, test suite is warning-free, packages are Hex-publishable

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion — **BLOCKS all user stories**
- **US1 (Phase 3)**: Depends on Foundational phase — core package orchestration
- **US2 (Phase 4)**: Depends on US1 — validates Jido interplay against working package
- **US3 (Phase 5)**: Depends on Foundational — can run in parallel with US1/US2
- **US4 (Phase 6)**: Depends on Foundational — can run in parallel with US1/US2/US3
- **US5 (Phase 7)**: Depends on US1 (needs MessageInjector) — can run in parallel with US3/US4
- **US6 (Phase 8)**: Depends on US1, US3, US4, US5 — requires ALL packages to be extracted before demo migration
- **Polish (Phase 9)**: Depends on all user stories being complete
- **Coverage & Hex Readiness (Phase 10)**: Depends on Phase 9 — final quality gate

### User Story Dependencies

```
Phase 1: Setup
    │
    ▼
Phase 2: Foundational  ─────────────────────────────────────┐
    │                                                         │
    ▼                                                         │
Phase 3: US1 (jido_murmur core)                             │
    │                    ┌──────────────────────┐            │
    ▼                    ▼                      ▼            ▼
Phase 4: US2 ──┐   Phase 5: US3        Phase 6: US4    Phase 7: US5
(interplay)    │   (web components)    (plugin pkgs)   (composable xform)
               │        │                   │               │
               ▼        ▼                   ▼               │
            Phase 8: US6 (demo app) ◄───────────────────────┘
                         │
                         ▼
                    Phase 9: Polish
                         │
                         ▼
                    Phase 10: Coverage &
                    Hex Readiness
```

### Within Each User Story

- Implementation tasks before test tasks (extraction/creation first, then validation)
- Schemas before contexts
- Core modules before dependent modules (e.g., Runner depends on PendingQueue, LLM, Catalog)
- Plugins/Actions before AgentHelper (helper composes them)
- Tasks marked [P] within a story can run in parallel

### Parallel Opportunities

**After Foundational completes, these can execute concurrently:**
- US1 (Phase 3) — jido_murmur core orchestration
- US3 (Phase 5) — jido_murmur_web components (only needs schemas from Foundational)
- US4 (Phase 6) — plugin packages (only needs schemas from Foundational)

**Within each phase, [P] tasks can run in parallel:**
- Phase 1: T003–T006 (package skeletons) in parallel
- Phase 2: T010–T013 (schemas), T016–T017 (ETS), T020–T022 (LLM) in parallel
- Phase 3: T026–T034 (module extractions) in parallel after T025 (Runner)
- Phase 5: T050–T057 (all 8 components) in parallel
- Phase 6: T068–T070 (task tools), T074–T075 (arxiv tools) in parallel

---

## Parallel Example: User Story 1

```
# After Foundational phase completes:

# Batch 1 — Extract Runner (others depend on it):
  T025: Extract Runner to apps/jido_murmur/lib/jido_murmur/runner.ex

# Batch 2 — Extract all independent modules in parallel:
  T026: Extract Catalog       ─┐
  T027: Extract UITurn         │
  T028: Extract StreamingPlugin│  All [P] — different files, no cross-deps
  T029: Extract ArtifactPlugin │
  T030: Extract Artifact       │
  T031: Extract TellAction     │
  T032: Extract StoreArtifact  │
  T033: Extract MessageInjector│
  T034: Extract TeamInstructions─┘

# Batch 3 — Modules depending on Batch 2:
  T035: Create AgentHelper (composes plugins/actions)
  T036: Add telemetry events

# Batch 4 — All unit tests in parallel:
  T037–T043: Unit tests (all [P])

# Batch 5 — Integration test (requires all above):
  T044: End-to-end message flow test
```

---

## Parallel Example: User Story 3 (Web Components)

```
# All 8 components can be extracted in parallel (separate files):
  T050–T057: ChatMessage, ChatStream, AgentHeader, MessageInput,
             StreamingIndicator, AgentSelector, WorkspaceList, ArtifactPanel

# Then sequential:
  T058: Unified Components import module
  T059: Copy templates for generator
  T060: Install generator

# All component tests in parallel:
  T061–T063: Component render tests
  T064: Generator test
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (umbrella structure)
2. Complete Phase 2: Foundational (config, schemas, ETS, storage, tests)
3. Complete Phase 3: User Story 1 (core orchestration, all jido_murmur modules)
4. **STOP and VALIDATE**: Test jido_murmur in isolation — verify a test agent can send messages, stream, persist
5. This gives a usable core package without web components or plugin packages

### Incremental Delivery

1. **Setup + Foundational** → Umbrella compiles, schemas exist, tests run
2. **US1** → jido_murmur is functional (MVP!)
3. **US2** → Jido interplay validated (design confidence)
4. **US3 + US4** → Web components + plugin packages (can parallelize)
5. **US5** → Composable transformers (advanced feature)
6. **US6** → Demo app migration (full validation)
7. **Polish** → Coverage, docs, Hex readiness

### Parallel Team Strategy

With multiple developers after Foundational completes:

1. **Developer A**: US1 (jido_murmur core) → US2 (interplay) → US6 (demo app)
2. **Developer B**: US3 (web components) → US5 (composable transformers)
3. **Developer C**: US4 (plugin packages: jido_tasks + jido_arxiv)
4. All converge for US6 (demo migration) and Phase 9 (polish)

---

## Notes

- [P] tasks = different files, no dependencies on in-progress tasks
- [Story] label maps each task to its user story for traceability
- Each user story should be independently completable and testable
- Module renames follow the mapping in plan.md §4.1 (Murmur.* → JidoMurmur.*, etc.)
- All ETS tables use `jido_murmur_` prefix per research.md R2
- All DB tables use `jido_murmur_` or `jido_tasks` prefix per data-model.md
- Migration generators follow the Oban pattern per research.md R3
- Config uses Application environment per research.md R4
- Telemetry events follow `[:jido_murmur, ...]` convention per research.md R6
- Test isolation uses Ecto sandbox per research.md R7
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
