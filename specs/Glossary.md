# Glossary

| Term | Definition |
|------|-----------|
| Agent | An AI-powered entity within a workspace that can receive messages, call tools, produce artifacts, and communicate with other agents. Backed by a Jido agent with an LLM. |
| Workspace | A container for a group of agents and their shared context (conversations, tasks, artifacts). |
| Runner | The execution loop in `jido_murmur` that processes an agent's message queue, calls the LLM, and dispatches tool calls and responses. |
| PendingQueue | A message buffer for agents that are busy. Incoming messages are queued and delivered when the agent finishes its current turn. |
| Plugin | A Jido plugin that hooks into the agent lifecycle (e.g., StreamingPlugin for token streaming, ArtifactPlugin for artifact emission). |
| Artifact | A rich output produced by an agent (HTML, chart, paper display) that is rendered in the UI outside the chat message flow. |
| Tool | A function an agent can call during its turn (e.g., "tell" for agent-to-agent messaging, "add_task" for task management, "arxiv_search" for research). |
| Hibernate/Thaw | The persistence mechanism: hibernate serializes an agent's conversation state to PostgreSQL; thaw restores it on reconnection. |
| Signal | A Jido event envelope used for inter-component communication, planned to align with CloudEvents spec. |
| Profile | A configuration struct defining an agent's name, system prompt, available tools, and LLM model alias. |
| Umbrella | The Mix project structure where multiple independently publishable OTP applications share a single repository. |
| PubSub | Phoenix.PubSub — the real-time event bus connecting agents, plugins, and LiveView UI. |
