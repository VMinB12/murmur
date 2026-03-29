# Murmur Demo

A reference Phoenix LiveView application showcasing the full [Jido](https://github.com/agentjido/jido) multi-agent orchestration platform. Create workspaces, spawn AI agents with different profiles, and watch them collaborate in real time — with persistent conversations, streaming responses, artifacts, and a shared task board.

This is the demo app inside the [Murmur umbrella](../../README.md). It wires together the four library packages into a working application:

| Package | Role |
|---------|------|
| [`jido_murmur`](../jido_murmur/) | Core backend — Runner, Plugins, Storage, Schemas |
| [`jido_murmur_web`](../jido_murmur_web/) | Pre-built LiveView chat components |
| [`jido_tasks`](../jido_tasks/) | Task management tools for agents |
| [`jido_arxiv`](../jido_arxiv/) | arXiv academic research tools |

## Features

- **Multi-agent workspaces** — Add multiple agents, each with independent chat history
- **Agent profiles** — General conversational agent and arXiv research specialist
- **Real-time streaming** — Token-by-token responses rendered over WebSocket
- **Agent-to-agent messaging** — Agents collaborate via the "tell" tool with message queuing
- **Artifacts** — Agents produce rich outputs (paper lists, PDF viewer, custom renderers)
- **Shared task board** — Agents manage tasks collaboratively across a workspace
- **Split & unified views** — Side-by-side agent columns or a merged timeline with `@mention` routing
- **Persistent conversations** — History survives server restarts via hibernate/thaw to PostgreSQL

## Prerequisites

- Elixir 1.19+ / Erlang/OTP 28+
- PostgreSQL 17 (or Docker)
- An `OPENAI_API_KEY` environment variable

## Getting Started

From the **umbrella root** (`murmur/`):

```bash
# Start PostgreSQL via Docker
docker compose up -d

# Install deps, create DB, run migrations, seed data
mix setup

# Start the server
mix phx.server
```

Visit [localhost:4000](http://localhost:4000), create a workspace, add agents, and start chatting.

### Running standalone

If you prefer to work within the demo app directly:

```bash
cd apps/murmur_demo
mix deps.get
mix ecto.setup
mix phx.server
```

## Routes

| Path | LiveView | Description |
|------|----------|-------------|
| `/` | `WorkspaceListLive` | List workspaces, create new ones |
| `/workspaces` | `WorkspaceListLive` | Same as above |
| `/workspaces/:id` | `WorkspaceLive` | Multi-agent chat interface |

A development dashboard is available at `/dev/dashboard` when running in dev mode.

## Project Layout

```
murmur_demo/
├── lib/
│   ├── murmur/
│   │   ├── application.ex      # OTP supervision tree
│   │   ├── jido.ex             # Jido framework setup with Ecto storage
│   │   ├── repo.ex             # PostgreSQL Ecto repository
│   │   └── agents/profiles/    # Agent profile definitions
│   │       ├── general_agent.ex
│   │       └── arxiv_agent.ex
│   └── murmur_web/
│       ├── router.ex           # Route definitions
│       ├── endpoint.ex         # Phoenix endpoint + WebSocket
│       ├── live/
│       │   ├── workspace_list_live.ex   # Workspace management
│       │   └── workspace_live.ex        # Multi-agent chat UI
│       └── components/
│           ├── artifacts.ex             # Artifact rendering pipeline
│           └── core_components.ex       # Phoenix UI components
├── assets/                     # JS, CSS, vendor deps
├── config/                     # App-level configuration
├── priv/
│   ├── repo/migrations/        # Ecto migrations
│   └── static/                 # Static assets
└── test/                       # Tests
```

## Configuration

Key configuration lives in `config/config.exs` at the umbrella root:

```elixir
# Connect library packages to this app's Repo and PubSub
config :jido_murmur,
  repo: Murmur.Repo,
  pubsub: Murmur.PubSub,
  profiles: [GeneralAgent, ArxivAgent]

config :jido_tasks,
  repo: Murmur.Repo,
  pubsub: Murmur.PubSub
```

Database defaults (dev):
- **Host:** `localhost:5432`
- **Database:** `murmur_dev`
- **Credentials:** `postgres:postgres`

## Testing

```bash
# From umbrella root — run all tests
mix test

# Run only murmur_demo tests
mix test --app murmur_demo

# Run a specific test file
mix test apps/murmur_demo/test/murmur_web/live/workspace_live_test.exs
```

## Development

```bash
# Format, compile, lint, and test in one step
mix precommit
```

Live reload is enabled in dev — changes to `.ex`, `.heex`, `.js`, and `.css` files trigger automatic browser refresh.
