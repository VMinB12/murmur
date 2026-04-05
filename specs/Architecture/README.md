# Architecture

## System Overview

Murmur is a real-time multi-agent chat platform built as an Elixir/Phoenix umbrella project. It enables users to create workspaces populated with AI agents that can converse with humans and each other, produce rich artifacts, and collaboratively manage tasks — all with persistent history and autonomous server-side execution.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         murmur_demo                             │
│                  (Reference Phoenix application)                │
│ LiveView ←→ PubSub ←→ Ingress ←→ Runner ←→ LLM                │
└──────┬──────────────┬──────────────┬──────────────┬─────────────┘
       │              │              │              │
┌──────▼──────┐ ┌─────▼──────┐ ┌────▼─────┐ ┌─────▼──────┐
│jido_murmur  │ │jido_murmur │ │jido_tasks│ │jido_arxiv  │
│  _web       │ │  (core)    │ │          │ │            │
│ LiveView    │ │ Runner,    │ │ Task     │ │ arXiv      │
│ Components  │ │ Plugins,   │ │ mgmt     │ │ search &   │
│             │ │ Storage,   │ │ tools    │ │ display    │
│             │ │ Schemas    │ │          │ │            │
└─────────────┘ └──────┬─────┘ └──────────┘ └────────────┘
                       │
               ┌───────▼───────┐  ┌──────────────┐  ┌──────────────┐
               │jido_artifacts │  │  jido_sql     │  │  jido (dep)  │
               │ Artifact      │  │  SQL agent    │  │  Agent       │
               │ system        │  │  plugin       │  │  framework   │
               └───────────────┘  └──────────────┘  └──────────────┘
                                         │
                                    PostgreSQL
```

## Key Components

| Component | Responsibility |
|-----------|---------------|
| `murmur_demo` | Reference Phoenix 1.8 application. Hosts LiveView UI, PubSub, Ecto Repo, and agent profile configuration. |
| `jido_murmur` | Core backend: Ingress coordinator, Runner (single-run execution), Plugins (streaming, artifacts), Storage.Ecto (conversation persistence), Schemas. |
| `jido_murmur_web` | Pre-built LiveView components for the chat interface — split/unified views, message rendering, workspace management. |
| `jido_tasks` | Task management Jido.Action tools — agents collaboratively manage a shared task board. |
| `jido_arxiv` | arXiv academic research tools — search and paper display as agent actions. |
| `jido_artifacts` | Artifact production system — agents emit rich artifacts (HTML, charts, papers) that render in the UI. |
| `jido_sql` | SQL agent plugin — natural-language-to-SQL query execution against a target database, with safety guardrails. |

## Technology Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| Language | Elixir 1.15+ / OTP | Concurrency, fault tolerance, real-time via lightweight processes |
| Web framework | Phoenix 1.8 + LiveView | Real-time UI with server-rendered HTML over WebSocket |
| Agent framework | Jido | Composable agent actions, signals, plugins, and supervision |
| AI/LLM | jido_ai + Req | Model-agnostic LLM integration via configurable aliases |
| Database | PostgreSQL + Ecto | Relational storage for conversations, tasks, artifacts |
| PubSub | Phoenix.PubSub | Real-time event distribution between agents and UI |
| Build | Mix umbrella | Independent packages, shared config, single repo |
| CSS | Tailwind CSS v4 | Utility-first styling with new import-based config |

## Key Constraints & Trade-offs

- **Umbrella structure**: Each app (`jido_murmur`, `jido_tasks`, etc.) is designed to be independently publishable to Hex. This adds inter-app boundary discipline but increases coordination cost.
- **Jido dependency**: The agent runtime is tightly coupled to the Jido framework. This gives rich agent primitives but means Murmur evolves with Jido's API.
- **Phoenix PubSub for agent communication**: Agents use PubSub for real-time events. This is simple and performant in a single-node deployment but requires distributed PubSub (e.g., Redis adapter) for multi-node.
- **PostgreSQL as single data store**: All persistence (conversations, tasks, artifacts, SQL agent queries) goes through PostgreSQL. Scales well for the expected load but may need read replicas at scale.

## Canonical Boundaries

- **Actor identity boundary**: Murmur now treats current actor and origin actor as explicit data, not as overloaded `sender_name` strings. Canonical ingress metadata is projected once into runtime context and visible message payloads, then reused consistently downstream.
- **Display projection boundary**: UI consumers are expected to render canonical display messages instead of raw thread-entry payloads. Shared and demo-owned views branch on actor semantics rather than parsing content prefixes or comparing display labels such as `"You"`.
- **Presentation-owned wording**: Human-facing labels remain a rendering concern. Runtime payloads carry actor metadata; host apps choose wording like `"You"` or `"A human"` at the UI edge.

## Sub-documents

- [ecosystem.md](ecosystem.md) — How packages compose into a full application
- [observability.md](observability.md) — Trace boundaries, Phoenix session grouping, discussion lifecycle, and cross-agent correlation
- [jido-murmur.md](jido-murmur.md) — Core backend: Runner, Storage, Schemas, Plugins
- [jido-murmur-web.md](jido-murmur-web.md) — LiveView component library
- [jido-artifacts.md](jido-artifacts.md) — Artifact emission and management system
- [jido-tasks.md](jido-tasks.md) — Task management tools and signals
- [jido-arxiv.md](jido-arxiv.md) — arXiv research tools
- [jido-sql.md](jido-sql.md) — SQL agent plugin
- [murmur-demo.md](murmur-demo.md) — Reference Phoenix application
