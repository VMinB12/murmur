# Quickstart: Multi-Agent Chat Interface

**Feature**: `001-multi-agent-chat`  
**Date**: 2026-03-25

## Prerequisites

- Elixir ≥ 1.15 and Erlang/OTP installed
- PostgreSQL running (via Docker Compose: `docker compose up -d`)
- LLM API key configured in environment (e.g., `OPENAI_API_KEY`)

## Setup

```bash
# Clone and enter the project
cd murmur

# Install deps, create DB, run migrations, seed data
mix setup
```

## Run

```bash
# Start the Phoenix server
mix phx.server

# Or with IEx for interactive debugging
iex -S mix phx.server
```

Visit [http://localhost:4000](http://localhost:4000).

## Verify Feature

1. **Create a workspace**: Navigate to the workspaces page and create a new workspace
2. **Add an agent**: Open the agent catalog, select an agent profile, give it a display name, and add it
3. **Send a message**: Type a message in the agent's input box and submit
4. **Verify streaming**: Observe tokens appearing incrementally in the agent's chat column
5. **Add a second agent**: Add another agent from the catalog
6. **Verify independence**: Send messages to each agent independently
7. **Verify persistence**: Refresh the page — all messages and agents should be restored
8. **Verify inter-agent tell** (P3): Prompt an agent with a task that requires the other agent's help; observe the "tell" message appear in the second agent's column

## Run Tests

```bash
# Full test suite
mix test

# Feature-specific tests
mix test test/murmur/workspaces_test.exs
mix test test/murmur/chat_test.exs
mix test test/murmur/agents/
mix test test/murmur_web/live/workspace_live_test.exs

# Pre-commit checks (format + compile + credo + dialyzer + tests)
mix precommit
```

## Key Paths

| What | Path |
|------|------|
| Workspace context | `lib/murmur/workspaces/` |
| Chat context | `lib/murmur/chat/` |
| Agent modules | `lib/murmur/agents/` |
| Workspace LiveView | `lib/murmur_web/live/workspace_live.ex` |
| PubSub contracts | `specs/001-multi-agent-chat/contracts/pubsub.md` |
| Data model | `specs/001-multi-agent-chat/data-model.md` |
