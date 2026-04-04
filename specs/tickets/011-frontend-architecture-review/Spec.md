# Spec: Frontend Architecture Review — murmur_web & murmur_demo

## User Stories

### US-1: Generic multi-agent workspace shell (Priority: P1)

**As a** Phoenix application developer using `jido_murmur_web`, **I want** the library to provide a generic multi-agent chat workspace with a separate artifact panel, **so that** I can embed Murmur in my own application without inheriting agent-specific business logic.

**Independent test**: Integrate the package into a host app that does not include SQL or arXiv features and verify the workspace UI still compiles and supports chat plus artifact browsing.

### US-2: Consumer-owned domain presentation (Priority: P1)

**As a** product developer building agent experiences on Murmur, **I want** agent- and plugin-specific artifact presentation and follow-up behaviors to live in the consuming application or the responsible package, **so that** domain behavior can evolve independently of the generic frontend library.

**Independent test**: Provide a custom artifact type and specialized UI behavior from the host application, and verify the generic library does not need to know that artifact's schema or business rules.

### US-3: Cohesive workspace interaction model (Priority: P2)

**As a** workspace user collaborating with multiple agents, **I want** the chat surfaces, artifact navigation, and supporting controls to use a consistent DaisyUI-based interaction model, **so that** the interface feels coherent while agents stream messages and produce artifacts.

**Independent test**: Review the workspace in split and unified modes and verify equivalent interactions use consistent visual patterns, including empty, loading, and expandable detail states.

### US-4: Maintainable frontend boundaries (Priority: P2)

**As a** Murmur maintainer, **I want** the workspace frontend organized around clear generic versus app-specific responsibilities, **so that** the design can change without entangling reusable components with demo-specific logic.

**Independent test**: Inspect the frontend modules and verify reusable package code contains only shared chat and artifact workspace concerns while demo-owned modules encapsulate domain integrations and specialized behaviors.

## Acceptance Criteria

- [ ] `jido_murmur_web` can be used as a generic multi-agent workspace UI without requiring compile-time or runtime knowledge of agent-specific packages such as SQL or arXiv features.
- [ ] The generic workspace experience continues to support both chat interactions and a separate artifact panel, and host applications can decide how agent-specific artifacts are rendered or acted on.
- [ ] Domain-specific artifact schemas, labels, presentation rules, and follow-up actions are defined outside `jido_murmur_web`.
- [ ] `murmur_demo` continues to demonstrate SQL and arXiv workflows, but those workflows are expressed through demo-owned or package-owned integrations rather than generic library assumptions.
- [ ] The workspace UI preserves the current high-level capabilities of split-view and unified-view chat, but the visual design and component structure may change if the resulting experience is cleaner and more coherent.
- [ ] Equivalent interaction patterns across the workspace use the project's adopted DaisyUI design language consistently, including chat presentation, artifact navigation, expandable metadata or tool output, and empty or loading states.
- [ ] Unknown or unsupported artifact types still render safely through a generic fallback experience instead of assuming a domain-specific data shape.
- [ ] The ticket may introduce breaking frontend API or template changes where needed to achieve cleaner boundaries and better separation of concerns.

## Scope

### In Scope

- Redefining the boundary between `jido_murmur_web` and consuming applications such as `murmur_demo`
- Keeping `jido_murmur_web` focused on generic multi-agent chat and artifact workspace concerns
- Moving or isolating agent- and plugin-specific presentation and actions into app-owned or package-owned code
- Improving the workspace design while preserving the core layout concepts of chat surfaces plus a separate artifact panel
- Standardizing workspace interactions around the project's DaisyUI-based design system
- Refactoring frontend modules to make shared responsibilities easier to understand and extend

### Out of Scope

- Preserving backward compatibility for existing frontend component APIs, DOM structure, or CSS hooks
- Changing the underlying backend agent runtime, conversation model, or artifact transport contracts unless required by a separately approved ticket
- Replacing DaisyUI with a different primary component system
- Expanding `jido_murmur_web` into a product-specific UI layer for SQL, arXiv, or other domain plugins
- Reworking unrelated backend packages or non-workspace screens beyond what is needed to support the new frontend boundary