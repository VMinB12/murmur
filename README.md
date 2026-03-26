# Murmur

A real-time multi-agent chat interface built with Phoenix LiveView and the [Jido](https://github.com/agentjido/jido) agent framework. Create workspaces, add AI agents, and watch them collaborate — with persistent conversations and agent-to-agent communication.

## Features

- **Multi-agent workspaces** — Add multiple AI agents, each with independent chat history
- **Agent-to-agent messaging** — Agents communicate via the "tell" tool, with message queuing when busy
- **Real-time streaming** — Token-by-token responses over WebSocket
- **Persistent conversations** — History survives server restarts via hibernate/thaw
- **Autonomous execution** — Agents continue processing server-side during disconnects

## Getting Started

**Prerequisites:** Elixir, Erlang/OTP, PostgreSQL (or Docker), and an `OPENAI_API_KEY`.

```bash
# Start PostgreSQL via Docker
docker compose up -d

# Install deps, create DB, run migrations
mix setup

# Start the server
mix phx.server
```

Visit [localhost:4000](http://localhost:4000), create a workspace, add agents, and start chatting.

## Development

```bash
mix test            # Run tests
mix precommit       # Format + compile + lint + dialyzer + test
```
