---
name: jido
description: Use when working with Jido 2.0 agent framework — defining agents, actions, plugins, signals, strategies, and the AgentServer runtime. Use when building multi-agent or AI-powered features in Elixir.
---

This section is the authoritative reference for Jido's primitives. These pages aren't tutorials - they explain _what_ each primitive is, _why_ it exists, and _how_ it fits with the others. Read them in order the first time through; each concept builds on the one before it.

## The core model

Jido separates concerns that most agent frameworks collapse together. Actions are pure functions - validated, composable units of work that transform data. Signals are the universal message format, built on CloudEvents, that carry events and commands through the system. Agents are typed state structs with a behavior contract: pass in an action, get back updated state and directives. Directives are declarative descriptions of side effects - the agent never executes them directly. The runtime picks up those directives and executes them inside a supervised GenServer, keeping your domain logic deterministic and testable. Execution, the pipeline that actually runs actions, handles validation, chaining, retry, and compensation so callers don't have to.

Beyond the core, Jido has three cognitive pillars: Thread records what happened (the append-only interaction log), Memory stores what the agent currently believes and intends (the mutable cognitive substrate), and Strategy controls how actions execute. Sensors bridge external events into the signal layer, Plugins package reusable capabilities for composition across agents, and Persistence lets agents survive restarts through hibernate, thaw, and storage adapters.

## Concepts (root files) — read in order

1. `actions.md` — Pure functions: validated, composable units of work
2. `signals.md` — CloudEvents-based message envelopes for commands & events
3. `agents.md` — Typed state structs with a command interface
4. `directives.md` — Declarative side-effect descriptions returned by actions
5. `agent-runtime.md` — GenServer layer that executes directives & manages lifecycle
6. `sensors.md` — Stateless modules bridging external events into signals
7. `strategy.md` — Pluggable execution models for action processing
8. `plugins.md` — Composable behavior bundles (actions, routes, state)
9. `execution.md` — Action pipeline: validation, chaining, retry, compensation
10. `threads.md` — Append-only interaction log
11. `memory.md` — Mutable cognitive substrate (beliefs, goals)
12. `persistence.md` — Hibernate/thaw and storage adapters
13. `testing.md` — Testing patterns for agents and actions

## getting-started/

- `index.md` — Getting started overview
- `installation.md` — Installation & deps setup
- `first-agent.md` — Build your first agent
- `first-llm-agent.md` — Build your first LLM-powered agent
- `elixir-developers.md` — Orientation for Elixir developers
- `new-to-elixir.md` — Orientation for developers new to Elixir

## guides/

- `index.md` — Guides overview
- `building-a-weather-agent.md` — End-to-end weather agent walkthrough
- `debugging-and-troubleshooting.md` — Debugging patterns & diagnostics
- `error-handling-and-recovery.md` — Error handling, retry, compensation
- `persistence-and-checkpoints.md` — Persistence & checkpoint patterns
- `testing-agents-and-actions.md` — Comprehensive testing guide
- `cookbook/chat-response.md` — Chat response cookbook recipe

## learn/ — step-by-step tutorials

- `index.md` — Tutorials overview
- `first-workflow.md` — Your first workflow
- `ai-agent-with-tools.md` — AI agent with tool use
- `ai-chat-agent.md` — Multi-turn chat agent
- `memory-and-retrieval-augmented-agents.md` — Memory & RAG agents
- `multi-agent-orchestration.md` — Multi-agent orchestration
- `parent-child-agent-hierarchies.md` — Parent-child agent hierarchies
- `plugins-and-composable-agents.md` — Plugins & composable agents
- `reasoning-strategies-compared.md` — Reasoning strategies compared
- `sensors-and-real-time-events.md` — Sensors & real-time events
- `state-machines-with-fsm.md` — State machines with FSM
- `task-planning-and-execution.md` — Task planning & execution

## reference/

- `index.md` — Reference overview
- `behavior-first-architecture.md` — Behavior-first architecture design
- `configuration.md` — Configuration keys & options
- `glossary.md` — Term definitions
- `req-llm-and-llmdb.md` — ReqLLM & LLM DB integration
- `telemetry-and-observability.md` — Telemetry, metrics, observability
- `why-not-just-a-genserver.md` — Why Jido vs plain GenServer

## ecosystem/ — package docs

- `jido.md` — Core runtime package
- `jido_action.md` — Action library
- `jido_ai.md` — LLM orchestration & reasoning
- `jido_signal.md` — Signal types & routing
- `jido_memory.md` / `jido_memory_os.md` — Memory subsystems
- `jido_chat.md` / `jido_chat_discord.md` / `jido_chat_telegram.md` — Chat integrations
- `jido_mcp.md` — Model Context Protocol
- `jido_claude.md` / `jido_gemini.md` / `jido_bedrock.md` — LLM provider adapters
- `jido_browser.md` / `jido_shell.md` / `jido_vfs.md` — Tool packages
- `jido_workspace.md` / `jido_codex.md` / `jido_opencode.md` — Dev tools
- `jido_cluster.md` / `jido_messaging.md` — Distributed infrastructure
- `jido_otel.md` / `jido_live_dashboard.md` — Observability
- `jido_character.md` / `jido_eval.md` / `jido_evolve.md` — Specialized agents
- `jido_amp.md` / `jido_behaviortree.md` / `jido_runic.md` — Execution strategies
- `jido_harness.md` / `jido_lib.md` / `jido_studio.md` — Supporting libraries
- `ash_jido.md` — Ash Framework integration
- `llm_db.md` / `req_llm.md` — LLM client libraries

## features/ — capability overviews

- `agents-that-self-heal.md` — Self-healing agent patterns
- `beam-for-ai-builders.md` — Why BEAM for AI
- `beam-native-agent-model.md` — BEAM-native agent model
- `executive-brief.md` — Executive summary
- `how-agents-work.md` — How agents work internally
- `jido-vs-framework-first-stacks.md` — Jido vs other frameworks
- `llm-support.md` — LLM support & providers
- `multi-agent-coordination.md` — Multi-agent coordination
- `observe-everything.md` — Observability features
- `start-small.md` — Start small, scale up
- `tools.md` — Tool integration

## build/ — implementation guides

- `index.md` — Build overview
- `mixed-stack-integration.md` — Mixed-stack integration patterns
- `product-feature-blueprints.md` — Product feature blueprints
- `quickstarts-by-persona.md` — Quickstarts by role/persona
- `reference-architectures.md` — Reference architectures
