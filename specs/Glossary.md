# Glossary

| Term | Definition |
|------|-----------|
| Agent | An AI-powered entity within a workspace that can receive messages, call tools, produce artifacts, and communicate with other agents. Backed by a Jido agent with an LLM. |
| Workspace | A container for a group of agents and their shared context (conversations, tasks, artifacts). |
| Ingress Coordinator | The per-session process in `jido_murmur` that decides whether inbound input should start a fresh ask or be routed into the active run with native steering/inject semantics. |
| Runner | The execution path in `jido_murmur` that starts a single ask/await run, records observability, and broadcasts completion or failure. |
| Plugin | A Jido plugin that hooks into the agent lifecycle (e.g., StreamingPlugin for token streaming, ArtifactPlugin for artifact emission). |
| Artifact | A rich output produced by an agent (HTML, chart, paper display) that is rendered in the UI outside the chat message flow. |
| Tool | A function an agent can call during its turn (e.g., "tell" for agent-to-agent messaging, "add_task" for task management, "arxiv_search" for research). |
| Hibernate/Thaw | The persistence mechanism: hibernate serializes an agent's conversation state to PostgreSQL; thaw restores it on reconnection. |
| Signal | A Jido event envelope used for inter-component communication, planned to align with CloudEvents spec. |
| Profile | A configuration struct defining an agent's name, system prompt, available tools, and LLM model alias. |
| Umbrella | The Mix project structure where multiple independently publishable OTP applications share a single repository. |
| PubSub | Phoenix.PubSub — the real-time event bus connecting agents, plugins, and LiveView UI. |
