# Product Requirements Document

## Functional Requirements

### FR-1: Multi-agent workspaces

Users create workspaces and add multiple AI agents, each with independent chat history and configurable profiles.

### FR-2: Agent-to-agent messaging

Agents communicate with each other via the "tell" tool. Delivery is coordinated per target session so idle agents start a fresh run and busy agents receive native active-run follow-up input.

### FR-3: Real-time streaming

Token-by-token LLM responses are streamed over WebSocket to the LiveView UI, providing immediate feedback.

### FR-4: Persistent conversations

Chat history survives server restarts via hibernate/thaw storage. Agents resume context on reconnection.

### FR-5: Autonomous execution

Agents continue processing server-side during client disconnects. Work is not lost when a user closes the browser.

### FR-6: Artifact production

Agents produce rich artifacts (HTML, charts, research papers) that render in the UI via a pluggable artifact system.

### FR-7: Shared task board

Agents collaboratively manage tasks, enabling long-running convergence on complex goals across multiple agents.

### FR-8: Split and unified views

Users can view agent conversations side-by-side (split view) or as a merged timeline with `@mention` routing (unified view).

### FR-9: SQL agent plugin

Natural-language-to-SQL query execution with safety guardrails, schema introspection, and result formatting.

### FR-10: Modular Hex packages

Core functionality (`jido_murmur`, `jido_murmur_web`, `jido_tasks`, `jido_arxiv`) is published as independent Hex packages that other Phoenix applications can integrate.

## Non-Functional Requirements

### Performance

- Token streaming latency under 100ms from LLM response to UI render
- Support 10+ concurrent agents per workspace without degradation

### Security

- SQL agent enforces read-only queries and row limits by default
- No arbitrary code execution from agent tools
- User input sanitized through Phoenix's built-in XSS protection

### Scalability

- Umbrella structure supports independent scaling of components
- PubSub-based architecture allows distributed deployment with adapter swap

### Accessibility

- Standard Phoenix/LiveView accessibility patterns for the web UI

## Scope

### In Scope

- Multi-agent chat orchestration and UI
- Agent-to-agent communication
- Conversation persistence
- Artifact system
- Task management tools
- arXiv research tools
- SQL query tools
- Hex package publishing

### Out of Scope

- Multi-tenant SaaS hosting
- User authentication and authorization (delegated to host app)
- Mobile-native clients
- Non-LLM agent types

## Assumptions & Constraints

- Host application provides PostgreSQL, PubSub, and Ecto Repo
- LLM access requires an API key (currently OpenAI-focused via jido_ai aliases)
- Phoenix 1.8+ and Elixir 1.15+ are required
- Jido framework is a core dependency and its API stability affects Murmur
