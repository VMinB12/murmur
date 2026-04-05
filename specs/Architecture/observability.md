# Observability

## Purpose

This document defines Murmur's observability model for:

- root trace boundaries
- Phoenix session grouping
- immediate cross-agent causation
- workspace correlation

## Core Terms

### Agent Session

An agent session is the long-lived runtime identity of one agent process.

Examples:

- Alice's agent session id
- Bob's agent session id

This identity is exported as both `session.id` and `murmur.agent_id`.

Phoenix Sessions is therefore an agent-centric view: all traces produced by one agent appear under one Phoenix session row.

### Turn Trace

A turn trace is one executed react loop in `Runner`.

One turn produces:

- one root `AGENT` span
- zero or more child `LLM` spans
- zero or more child `TOOL` spans

The request id for that root turn is exported as `murmur.request_id`.

### Immediate Parent Causation

When one trace causes work on another idle agent, the new downstream root trace may record the direct upstream cause through `murmur.triggered_by_trace_id`.

This is intentionally immediate and local. Murmur does not infer or maintain a broader workflow, discussion, or lineage identifier.

### Workspace Correlation

`murmur.workspace_id` is the workspace/team correlation key.

It is used for filtering and cross-trace analysis, but it is **not** the Phoenix session grouping key.

## IDs And Their Roles

| Field | Meaning | Scope |
|---|---|---|
| `session.id` | Phoenix Sessions grouping key = executing agent session id | One agent runtime |
| `murmur.agent_id` | Concrete executing agent session id | One agent runtime |
| `murmur.request_id` | One executed react loop | One turn trace |
| `murmur.triggered_by_trace_id` | Immediate parent trace that caused a new downstream turn | One direct handoff |
| `murmur.workspace_id` | Workspace/team correlation id | One workspace |

## Session Grouping Rule

Phoenix Sessions groups traces by `session.id`.

Murmur exports `session.id` as the executing agent session id.

That means:

- all traces from Alice appear under Alice's Phoenix session row
- all traces from Bob appear under Bob's Phoenix session row
- long inactivity gaps do not create a new Phoenix session for the same agent

## Trace Boundary Rule

A new root trace starts only when an idle agent begins a new react loop.

Busy-run follow-up input does **not** create a second root trace. Instead, the input is routed into the active run and remains part of the same trace.

This preserves the rule:

- one executed react loop = one root trace

## What Starts A New Trace

A new root trace starts when inbound work reaches an idle agent and causes a fresh `ask/await` run.

Examples:

- a direct human message to an idle agent
- a tell or programmatic delivery to an idle agent
- any other inbound work that starts a fresh run after the prior run completed

## What Does Not Start A New Trace

These cases stay inside the active trace instead:

- steering delivered to an already-running agent
- injected follow-up input delivered to an already-running agent
- multiple follow-up messages absorbed by the same active loop

## What No Longer Exists In The Model

Murmur no longer treats any of the following as canonical observability concepts:

- discussion as the Phoenix session grouping unit
- `interaction_id` as an ingress or observability correlation field for this path
- `ConversationCache`
- `:conversation_session_timeout_ms`-based session rollover

## Examples

### Example 1: Two direct messages to Alice a week apart

User sends `hello` to Alice.

- Alice starts a new root trace `R-1`
- exported `session.id = Alice's agent session id`

A week later the user sends `can you expand on that?` to Alice.

- Alice starts a new root trace `R-2`
- exported `session.id` is still Alice's agent session id
- Phoenix shows both traces under one Alice session row

### Example 2: Alice tells idle Bob to do work

Alice is running trace `R-3` and tells Bob to do work.

- Bob is idle, so Bob starts a new root trace `R-4`
- Bob exports `session.id = Bob's agent session id`
- Bob may export `murmur.triggered_by_trace_id = R-3`

Alice and Bob do **not** collapse into one Phoenix session row, but the direct handoff remains visible.

### Example 3: Follow-up input arrives while Alice is still active

Alice is already processing trace `R-5` when more input arrives.

- the ingress coordinator routes that input into the active run
- no new root trace is created
- the follow-up work remains part of `R-5`

## Final Model

The observability model is:

- one Phoenix session per agent session
- one root trace per executed react loop
- optional immediate parent-trace causation for new downstream idle-agent work
- workspace/team identity remains separate correlation metadata
- no inferred discussion or workflow grouping id

## Related Modules

- `JidoMurmur.Runner`
- `JidoMurmur.Ingress`
- `JidoMurmur.Ingress.Coordinator`
- `JidoMurmur.Observability`
- `JidoMurmur.Observability.Store`
- `JidoMurmur.Telemetry.ReqLLMTracer`
- `MurmurWeb.WorkspaceLive`