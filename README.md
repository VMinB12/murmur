# Murmur

A real-time multi-agent chat interface built with Phoenix LiveView and the [Jido](https://github.com/agentjido/jido) agent framework. Create workspaces, add AI agents, and watch them collaborate — with persistent conversations and agent-to-agent communication.

## Features

![Murmur multi-agent workspace with three agents collaborating](example.png)

- **Multi-agent workspaces** — Add multiple AI agents, each with independent chat history
- **Agent-to-agent messaging** — Agents communicate via the "tell" tool, with message queuing when busy
- **Real-time streaming** — Token-by-token responses over WebSocket
- **Persistent conversations** — History survives server restarts via hibernate/thaw
- **Autonomous execution** — Agents continue processing server-side during disconnects
- **Artifacts** — Agents produce rich artifacts that affect the UI (e.g. the arXiv agent can display papers)
- **Shared task board** — Agents manage tasks collaboratively, allowing long-running convergence on complex goals
- **Split & unified views** — Side-by-side agent columns, or a merged timeline with `@mention` routing

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

## Architecture

```mermaid
flowchart LR
    UI[LiveView] --> Runner --> Agent --> LLM
    Agent -->|tell, tasks, artifacts| PubSub
    Runner -->|completion| PubSub
    PubSub -.->|stream to UI| UI
    Runner <-->|persist| DB[(PostgreSQL)]
```

## How It Works

When a user sends a message, the Runner queues it and calls the LLM. Tokens stream back in real-time via PubSub. If the agent decides to collaborate, it uses the **tell** tool to queue a message on another agent's Runner — kicking off a parallel conversation.

```mermaid
sequenceDiagram
    actor User
    participant UI as LiveView
    participant RA as Alice
    participant RB as Bob
    participant PS as PubSub

    User->>UI: send message
    UI->>RA: queue + call LLM
    RA-->>PS: stream tokens
    PS-->>UI: render live

    Note over RA: Alice tells Bob
    RA->>RB: tell("Bob", question)
    RB-->>PS: stream tokens
    PS-->>UI: render Bob live

    RA->>PS: done
    RB->>PS: done
    PS-->>UI: finalize
```

## Development

```bash
mix test            # Run tests
mix precommit       # Format + compile + lint + dialyzer + test
```
