# LLM Observability Analysis & Integration Plan

> **Goal:** Add developer-facing observability for LLM agent interactions — see what went into the model, what came out, token usage, tool calls, and nested trace trees — using a platform purpose-built for LLM semantics (not raw OTEL JSON dumps).

---

## 1. Current State

### What Already Exists

| Layer | Status | Details |
|-------|--------|---------|
| `:telemetry` plumbing | ✅ Active | Core `telemetry`, `telemetry_metrics`, `telemetry_poller` wired up |
| `Jido.Telemetry.setup()` | ✅ Active | Structured logging for agent commands, signal processing, directives, strategy ticks |
| `Jido.AI.Observe` | ✅ Active | LLM-specific event layer emitting `[:jido, :ai, :llm, :start\|:delta\|:complete\|:error]` |
| Token tracking | ✅ Active | `Signal.Usage` records `input_tokens`, `output_tokens`, `total_tokens`, `duration_ms`, `cost` per LLM call |
| Tool call telemetry | ✅ Active | `[:jido, :ai, :tool, :span\|:start\|:complete\|:error]` with tool name, call ID, retry count |
| Streaming deltas | ✅ Active | Per-token `[:jido, :ai, :llm, :delta]` events (feature-gated via `:llm_deltas`) |
| Sensitive data redaction | ✅ Active | `Jido.AI.Observe.sanitize_sensitive/1` auto-redacts API keys, tokens, secrets |
| Phoenix LiveDashboard | ✅ Active | VM metrics, DB queries, Phoenix endpoint metrics at `/dev/dashboard` |
| `Jido.Observe.Tracer` behaviour | ✅ Defined | Pluggable span interface (`span_start/2`, `span_stop/2`, `span_exception/4`) — **currently using NoopTracer** |
| JidoLiveDashboard | ⚠️ Installed but unused | Dep conflict: requires `jido ~> 2.0.0-rc.4`, potential mismatch with `jido_ai ~> 2.0`. Captures agent/directive lifecycle only — **no LLM-specific events** |
| External observability backend | ❌ None | No OpenTelemetry, no Arize Phoenix, no LangFuse, no LangSmith |
| LLM trace visualization | ❌ None | No way to inspect human/AI messages, tool calls, or trace trees visually |

### Telemetry Event Namespace (already emitting)

```
[:jido, :ai, :llm, :span]        # LLM call lifecycle span
[:jido, :ai, :llm, :start]       # LLM call start
[:jido, :ai, :llm, :delta]       # Streaming token chunks
[:jido, :ai, :llm, :complete]    # LLM call completion
[:jido, :ai, :llm, :error]       # LLM call error
[:jido, :ai, :tool, :span]       # Tool execution span
[:jido, :ai, :tool, :start]      # Tool start
[:jido, :ai, :tool, :complete]   # Tool completion
[:jido, :ai, :tool, :error]      # Tool error
[:jido, :ai, :tool, :timeout]    # Tool timeout
[:jido, :ai, :request, :*]       # Request lifecycle
[:jido, :ai, :strategy, *, :*]   # Strategy events
[:jido_murmur, :runner, :*]      # Runner lifecycle
[:jido_murmur, :streaming, :*]   # Signal broadcasting
[:jido_artifacts, :artifact, :*] # Artifact persistence
```

### Key Insight

The **instrumentation is already done**. Jido's AI layer emits rich, structured telemetry events with token counts, message content, tool calls, and correlation IDs. What's missing is a **backend** that understands LLM semantics and can display them to developers.

---

## 2. Platform Comparison

The user's requirement is clear: generic OTEL backends (Jaeger, Grafana Tempo, Datadog APM) won't suffice because they render LLM traces as unstructured JSON blobs. We need an LLM-aware platform.

### Candidate Platforms

| Platform | LLM-Aware | Self-Hosted | Free Tier | Elixir SDK | Jido Integration | Maturity |
|----------|-----------|-------------|-----------|------------|------------------|----------|
| **Arize Phoenix** | ✅ Full (OpenInference) | ✅ Docker | ✅ OSS | Via OTLP | ✅ Via AgentObs | High |
| LangFuse | ✅ Full | ✅ Docker | ✅ OSS | ❌ Python/JS only | ❌ Custom needed | High |
| LangSmith | ✅ Full | ❌ Cloud only | ⚠️ Limited | ❌ Python/JS only | ❌ Custom needed | High |
| Arize Cloud | ✅ Full | ❌ Cloud only | ⚠️ Limited | Via OTLP | ✅ Via AgentObs | High |
| LogFire | ⚠️ Partial | ❌ Cloud only | ⚠️ Limited | ❌ Python only | ❌ Custom needed | Medium |
| MLFlow | ⚠️ Partial | ✅ Self-hosted | ✅ OSS | ❌ Python only | ❌ Custom needed | High |
| Helicone | ✅ Full | ❌ Cloud only | ✅ Free tier | ❌ JS/proxy only | ❌ Custom needed | Medium |

### Why Arize Phoenix + AgentObs

Arize Phoenix is the clear winner for this stack:

1. **OpenInference semantic conventions** — defines standard attribute names for LLM inputs, outputs, tool calls, token usage. Phoenix parses these into a rich UI with chat message bubbles, tool call expandables, and cost dashboards
2. **Self-hosted** — `docker run -p 6006:6006 arizephoenix/phoenix:latest` — no vendor lock-in, no data leaving your infra
3. **Accepts standard OTLP** — any OpenTelemetry exporter can push spans to it
4. **AgentObs provides the Elixir bridge** — published to Hex, implements `Jido.Observe.Tracer`, translates metadata to OpenInference format

---

## 3. Does Jido Have a Native Solution?

**Short answer: No, but it's ready for one.**

### What Jido provides natively

- `Jido.Observe.Tracer` — a **behaviour** (interface) for span-based tracing, not an implementation
- `Jido.Observe.NoopTracer` — the default. Does nothing
- `Jido.AI.Observe` — emits rich telemetry events but no span export
- `Jido.Tracing.Context` — correlation IDs (`trace_id`, `span_id`, `parent_span_id`) auto-injected into events
- Sensitive data redaction built in to the AI observe layer

### What Jido does NOT provide

- No OpenTelemetry span creation
- No OpenInference attribute mapping
- No external backend export
- No visualization UI
- No `AgentObs.JidoTracer` equivalent in the core library

### Verdict

Jido designed the `Jido.Observe.Tracer` behaviour **specifically** to be filled by an external implementation like AgentObs. The architecture is plug-and-play — you configure a tracer module, and Jido dispatches all span lifecycle events to it automatically.

---

## 4. AgentObs Evaluation

### Overview

| Attribute | Value |
|-----------|-------|
| Package | `{:agent_obs, "~> 0.1.4"}` |
| License | MIT |
| Hex downloads | ~40k total |
| Dependencies | `jason`, `opentelemetry ~> 1.3`, `opentelemetry_api ~> 1.2`, `opentelemetry_exporter ~> 1.6`, `telemetry ~> 1.0` |
| Optional deps | `jido ~> 2.0`, `req_llm ~> 1.0` |
| Author | Edgar Gomes (`lostbean`) |
| Last release | v0.1.4 — March 11, 2026 (18 days ago) |

### How Integration Works

```
┌──────────────────────────────────────────────────┐
│                  Jido Framework                  │
│                                                  │
│  LLMGenerate ──┐                                 │
│  LLMStream  ───┼── Jido.Observe ──► Tracer ──────┤
│  ToolExec   ──┘       │                          │
│                       ▼                          │
│            :telemetry events                     │
│         (already emitting today)                 │
└──────────────────────────────────────────────────┘
                        │
                        ▼ Implements Jido.Observe.Tracer
┌──────────────────────────────────────────────────┐
│              AgentObs.JidoTracer                 │
│                                                  │
│  span_start/2 ──► Creates OTel span              │
│   └─ Maps metadata to OpenInference attributes   │
│  span_stop/2  ──► Sets result attrs, ends span   │
│  span_exception/4 ──► Records error, ends span   │
│                                                  │
│  Parent-child nesting via OTel context propagation│
└──────────────────────────────────────────────────┘
                        │
                        ▼ OTLP (gRPC or HTTP)
┌──────────────────────────────────────────────────┐
│              Arize Phoenix (local)               │
│                                                  │
│  • Chat message visualization (human/AI/tool)    │
│  • Token usage & cost dashboards                 │
│  • Nested span tree (agent → LLM → tool)         │
│  • Streaming delta inspection                    │
│  • Error trace analysis                          │
└──────────────────────────────────────────────────┘
```

### Minimal Configuration Required

```elixir
# mix.exs (in the app that runs agents)
{:agent_obs, "~> 0.1.4"}

# config/config.exs
config :agent_obs,
  enabled: true,
  handlers: [AgentObs.Handlers.Phoenix]

config :jido, :observability,
  tracer: AgentObs.JidoTracer

# config/runtime.exs
config :opentelemetry,
  span_processor: :batch,
  resource: [service: [name: "murmur"]]

config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf,
  otlp_endpoint: System.get_env("ARIZE_PHOENIX_OTLP_ENDPOINT", "http://localhost:6006")
```

That's it. **Zero code changes** to existing agents, directives, or plugins.

### Pros

| Pro | Why It Matters |
|-----|----------------|
| **Zero-code instrumentation** | Jido already emits events; AgentObs just plugs in as the tracer backend |
| **Drop-in `Jido.Observe.Tracer`** | `AgentObs.JidoTracer` implements exactly the behaviour Jido expects |
| **ReqLLM integration** | Project already uses `req_llm ~> 1.0` — optional auto-instrumentation available |
| **OpenInference semantics** | Arize Phoenix understands `input.value`, `output.value`, `llm.token_count.*`, `tool.name` etc. |
| **Self-hosted Phoenix** | Single Docker container, no SaaS dependency, no data exfiltration |
| **Active maintenance** | 5 releases, last 18 days ago, MIT license |
| **Sensitive data redaction** | Jido.AI.Observe already redacts secrets before they reach the tracer |
| **Dual-backend possible** | Can run Phoenix handler + Generic handler simultaneously for APM integration |
| **Fault-tolerant** | Built on OTP supervision; tracer failures are logged, never crash the app |
| **Existing compose.yaml** | Project already has `compose.yaml` — adding a Phoenix service is trivial |

### Cons / Risks

| Con | Severity | Mitigation |
|-----|----------|------------|
| **Early-stage library** (v0.1.4) | Medium | MIT license, small codebase (~2k LOC), easy to fork/patch if abandoned |
| **Single maintainer** (`lostbean`) | Medium | Same author as `req_llm` which Jido depends on — aligned incentives |
| **OpenTelemetry dependency tree** | Low | `opentelemetry ~> 1.3`, `opentelemetry_api ~> 1.2`, `opentelemetry_exporter ~> 1.6` — adds ~5 transitive deps |
| **Potential dep conflicts** | Low | `jido ~> 2.0` optional dep should match project's Jido version. Verify with `mix deps.get` |
| **No LangFuse handler (yet)** | Low | Phoenix handler covers same use case. Custom handler guide available if needed later |
| **Streaming delta events** | Low | Per-token spans may be noisy in Phoenix UI. Feature-gated behind `:llm_deltas` — can disable |
| **No prod-ready batching tuning** | Low | OTel batch processor defaults may need tuning for high-throughput prod scenarios |

---

## 5. Alternative: Build a Custom Tracer

Instead of using AgentObs, we could build a minimal `Jido.Observe.Tracer` implementation directly.

### What It Would Require

```elixir
defmodule Murmur.LLMTracer do
  @behaviour Jido.Observe.Tracer
  # 1. Add opentelemetry + opentelemetry_api + opentelemetry_exporter deps
  # 2. Implement span_start/2 — create OTel span, map metadata to OpenInference attrs
  # 3. Implement span_stop/2 — set measurements, end span
  # 4. Implement span_exception/4 — record error, end span
  # 5. Handle parent-child context propagation
  # 6. Map all Jido event prefixes to OpenInference span kinds
  # 7. Normalize conversation/messages to OpenInference input/output format
end
```

### Estimate: ~200-400 LOC for basic coverage

AgentObs already does this plus:
- ReqLLM auto-instrumentation
- Multiple handler support
- Comprehensive metadata translation
- 193 tests including integration tests

### Verdict: Not recommended

The custom approach duplicates work that AgentObs already provides and maintains. The only reason to go custom would be if AgentObs introduces breaking incompatibilities with our Jido version.

---

## 6. Recommended Integration Plan

### Phase 1: Local Dev Observability (Minimal Effort)

**Goal:** Every developer can see LLM inputs/outputs, token usage, and tool calls in a local UI.

1. Add dependencies:
   ```elixir
   # apps/jido_murmur/mix.exs or apps/murmur_demo/mix.exs
   {:agent_obs, "~> 0.1.4"}
   ```

2. Add Arize Phoenix to `compose.yaml`:
   ```yaml
   services:
     phoenix:
       image: arizephoenix/phoenix:latest
       ports:
         - "6006:6006"
         - "4317:4317"
   ```

3. Configure tracer (config changes only — no code changes):
   ```elixir
   # config/config.exs
   config :agent_obs,
     enabled: true,
     handlers: [AgentObs.Handlers.Phoenix]

   config :jido, :observability,
     tracer: AgentObs.JidoTracer

   # config/runtime.exs
   config :opentelemetry,
     span_processor: :batch,
     resource: [service: [name: "murmur"]]

   config :opentelemetry_exporter,
     otlp_protocol: :http_protobuf,
     otlp_endpoint: System.get_env("ARIZE_PHOENIX_OTLP_ENDPOINT", "http://localhost:6006")
   ```

4. Verify: run the app, trigger an agent conversation, open `http://localhost:6006`

**Expected trace tree in Phoenix:**
```
chat_session (agent)
  ├── openai:gpt-5-mini #1 (llm)
  │     input:  [{ role: "user", content: "..." }]
  │     output: [{ role: "assistant", content: "...", tool_calls: [...] }]
  │     tokens: { prompt: 150, completion: 80, total: 230 }
  ├── get_weather (tool)
  │     input:  { city: "Amsterdam" }
  │     output: { temp: 18, condition: "cloudy" }
  └── openai:gpt-5-mini #2 (llm)
        input:  [{ role: "user", content: "..." }, { role: "tool", content: "..." }]
        output: [{ role: "assistant", content: "The weather in Amsterdam..." }]
        tokens: { prompt: 280, completion: 45, total: 325 }
```

### Phase 2: Environment-Aware Configuration

- **Dev:** Traces → local Phoenix container
- **Test:** Traces disabled (or → test Phoenix instance for integration tests)
- **Prod:** Traces → hosted Arize Phoenix (or disabled until needed)

```elixir
# config/dev.exs
config :agent_obs, enabled: true

# config/test.exs
config :agent_obs, enabled: false

# config/prod.exs
config :agent_obs, enabled: true  # or gate behind env var
```

### Phase 3: Extended Instrumentation (Optional)

- Add `AgentObs.ReqLLM.trace_generate_text/3` wrappers for any direct `ReqLLM` calls outside Jido's directive system
- Add custom `AgentObs.trace_prompt/3` calls for prompt template rendering instrumentation
- Tune OTel batch processor for production throughput

---

## 7. Dependency Impact Assessment

### New Transitive Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `agent_obs` | ~> 0.1.4 | Core instrumentation |
| `opentelemetry` | ~> 1.3 | Span creation, context propagation |
| `opentelemetry_api` | ~> 1.2 | OTel API layer |
| `opentelemetry_exporter` | ~> 1.6 | OTLP span export |

### Compatibility Check

- `agent_obs` requires `jido ~> 2.0` (optional) — matches project's Jido version
- `agent_obs` requires `req_llm ~> 1.0` (optional) — matches project's ReqLLM version
- `agent_obs` requires `telemetry ~> 1.0` — project already uses `telemetry ~> 1.3`
- `agent_obs` requires `jason ~> 1.2` — project already uses Jason

**Risk: Low.** Run `mix deps.get` to verify no version conflicts before committing.

---

## 8. Decision Matrix

| Criterion | AgentObs + Arize Phoenix | Custom Tracer + Arize Phoenix | LangFuse (custom bridge) | Status Quo |
|-----------|--------------------------|-------------------------------|--------------------------|------------|
| Implementation effort | **Minimal** (config only) | Medium (~400 LOC) | High (build HTTP adapter) | None |
| LLM message visualization | ✅ Rich chat UI | ✅ Rich chat UI | ✅ Rich chat UI | ❌ None |
| Token usage tracking | ✅ Automatic | ✅ Manual mapping | ✅ Manual mapping | ❌ Lost |
| Tool call inspection | ✅ Automatic | ✅ Manual mapping | ✅ Manual mapping | ❌ Lost |
| Nested trace trees | ✅ Automatic | ⚠️ Manual ctx propagation | ⚠️ Custom nesting | ❌ None |
| Jido integration | ✅ Drop-in tracer | ⚠️ Must implement behaviour | ❌ Must intercept events | N/A |
| Self-hosted option | ✅ Docker | ✅ Docker | ✅ Docker | N/A |
| Maintenance burden | Low (upstream) | Medium (our code) | High (custom bridge) | None |
| ReqLLM auto-instrumentation | ✅ Built-in | ❌ Must build | ❌ Must build | ❌ None |
| Vendor flexibility | ✅ Swap OTLP endpoint | ✅ Swap OTLP endpoint | ❌ LangFuse-specific | N/A |

---

## 9. Recommendation

**Use AgentObs + Arize Phoenix.** This is effectively a **configuration-only change** because:

1. Jido already emits all the LLM/tool/agent telemetry events we need
2. AgentObs implements exactly the `Jido.Observe.Tracer` behaviour interface that Jido exposes
3. Arize Phoenix understands the OpenInference semantics that AgentObs produces
4. The project already uses `req_llm` which AgentObs optionally integrates with
5. The `compose.yaml` is already in place for adding the Phoenix container

There is **no Jido-native alternative** — the tracer behaviour was designed for exactly this kind of external plugin. AgentObs is the only published Hex package that fills this gap.

### Next Step

Run `/speckit.specify` with the observability feature description to create a formal spec, then proceed through the normal speckit workflow to implementation.

---

## 10. Multi-Agent Trace Grouping

### Requirements

1. **Per-workspace grouping** — filter and view all agent traces belonging to a workspace together in Phoenix
2. **Linked traces** — each agent has its own independent root trace, but traces within the same workspace are correlated so a developer can view all agent activity for a workspace in one place
3. **Individual agent drilldown** — still see each agent's full trace tree (LLM calls, tool calls) in isolation
4. **Cross-agent causation visibility** — when agent A "tells" agent B something, the relationship is discoverable (which agent triggered which)

### How the Multi-Agent System Works Today

```
Workspace (UUID)
  ├── AgentSession "researcher"  (session_id = UUID-1)
  │     └── AgentServer GenServer (registered as UUID-1)
  │           └── LLM calls, tool calls, signals
  ├── AgentSession "writer"      (session_id = UUID-2)
  │     └── AgentServer GenServer (registered as UUID-2)
  │           └── LLM calls, tool calls, signals
  └── AgentSession "reviewer"    (session_id = UUID-3)
        └── AgentServer GenServer (registered as UUID-3)
              └── LLM calls, tool calls, signals
```

Key facts:
- **Agent ID = Session ID** — a binary UUID, used as the process registry key, DB primary key, and PubSub topic component
- **Workspace ID** — groups agents; all PubSub topics follow `workspace:{wid}:agent:{sid}:...`
- **TellAction** — fire-and-forget inter-agent messaging. Agent A's tool call sends a message to agent B's queue via `Runner.send_message/2`. Agent B processes it asynchronously in its own drain loop
- **No shared trace context** — currently each agent's Jido tracing context is process-local (stored in process dictionary). When TellAction fires, no trace ID is propagated to the target agent

### OpenInference + Phoenix: Available Grouping Mechanisms

Phoenix and OpenInference provide three complementary mechanisms that map well to our needs:

#### 1. Projects (= environment/service separation)

A **project** in Phoenix is a top-level container for traces. Set via the OTel resource `service.name` attribute:

```elixir
config :opentelemetry,
  resource: [service: [name: "murmur"]]
```

All traces from this service appear under the "murmur" project. This is already handled by the basic AgentObs setup and doesn't need per-workspace customization.

#### 2. Sessions (= workspace grouping)

OpenInference defines `session.id` as a reserved span attribute. Phoenix has a dedicated **Sessions** tab that:
- Groups all traces sharing the same `session.id`
- Shows a timeline of interactions
- Provides a chat-like UI for input/output sequences
- Supports searching/filtering across session content

**This is the primary mechanism for workspace grouping.** By setting `session.id` to the `workspace_id`, all agent traces within that workspace are grouped together in the Phoenix Sessions view.

#### 3. Tags + Metadata (= agent identity within a session)

OpenInference supports:
- `tag.tags` — list of strings for categorizing spans (e.g., `["workspace:abc123", "agent:researcher"]`)
- `agent.name` — the name of the agent a span represents
- `metadata` — arbitrary JSON string for additional context
- `user.id` — identifies the triggering user

These allow filtering within a session to see only one agent's traces, or to identify which agent produced which trace.

### Proposed Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Arize Phoenix UI                      │
│                                                         │
│  Project: "murmur"                                      │
│  ┌───────────────────────────────────────────────────┐  │
│  │ Sessions tab → filter by workspace_id             │  │
│  │                                                    │  │
│  │  Session: workspace-uuid-abc                       │  │
│  │  ├── Trace: "researcher" agent                     │  │
│  │  │     ├── gpt-5-mini (LLM)                       │  │
│  │  │     ├── tell → writer (TOOL)                    │  │
│  │  │     └── gpt-5-mini (LLM)                       │  │
│  │  ├── Trace: "writer" agent                         │  │
│  │  │     ├── gpt-5-mini (LLM)                       │  │
│  │  │     ├── create_artifact (TOOL)                  │  │
│  │  │     └── gpt-5-mini (LLM)                       │  │
│  │  └── Trace: "reviewer" agent                       │  │
│  │        └── gpt-5-mini (LLM)                        │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  Traces tab → filter by tag "agent:researcher"          │
│  or search by agent.name                                │
└─────────────────────────────────────────────────────────┘
```

### Implementation: What Needs to Change

The core idea: **inject `workspace_id` and agent identity into the OTel span attributes** so Phoenix can group and filter them. This requires a thin wrapper around the tracer, not changes to application code.

#### Option A: Custom Tracer Wrapper (Recommended)

Create a tracer module that wraps `AgentObs.JidoTracer`, enriching every span with workspace and agent metadata before delegating:

```elixir
defmodule Murmur.ObsTracer do
  @behaviour Jido.Observe.Tracer

  @impl true
  def span_start(event_prefix, metadata) do
    enriched = metadata
    |> put_session_id()      # workspace_id → session.id
    |> put_agent_identity()  # agent display name → agent.name + tags
    |> put_causation_link()  # if triggered by another agent, record it

    AgentObs.JidoTracer.span_start(event_prefix, enriched)
  end

  @impl true
  def span_stop(span_ctx, measurements) do
    AgentObs.JidoTracer.span_stop(span_ctx, measurements)
  end

  @impl true
  def span_exception(span_ctx, kind, reason, stacktrace) do
    AgentObs.JidoTracer.span_exception(span_ctx, kind, reason, stacktrace)
  end

  # --- Enrichment ---

  defp put_session_id(metadata) do
    # Jido already passes :agent_id (= session.id) in metadata.
    # Look up the workspace_id for this agent session and set it as
    # the OpenInference session.id so Phoenix groups by workspace.
    case lookup_workspace_id(metadata[:agent_id]) do
      nil -> metadata
      workspace_id -> Map.put(metadata, :session_id, workspace_id)
    end
  end

  defp put_agent_identity(metadata) do
    case lookup_display_name(metadata[:agent_id]) do
      nil -> metadata
      name ->
        metadata
        |> Map.put(:agent_name, name)
        |> Map.update(:tags, [agent_tag(name)], &[agent_tag(name) | &1])
    end
  end

  defp put_causation_link(metadata) do
    # If this span was triggered by a TellAction, the hop_count
    # and sender_name are available in the tool context.
    # Record them as metadata for cross-agent correlation.
    metadata
  end

  defp agent_tag(name), do: "agent:#{name}"

  defp lookup_workspace_id(nil), do: nil
  defp lookup_workspace_id(agent_id) do
    # Cache this lookup (ETS or process dictionary) to avoid
    # hitting the DB on every span. Agent sessions are long-lived.
    case JidoMurmur.Workspaces.get_agent_session(agent_id) do
      %{workspace_id: wid} -> wid
      _ -> nil
    end
  end

  defp lookup_display_name(nil), do: nil
  defp lookup_display_name(agent_id) do
    case JidoMurmur.Workspaces.get_agent_session(agent_id) do
      %{display_name: name} -> name
      _ -> nil
    end
  end
end
```

Configuration:

```elixir
# Use our wrapper instead of AgentObs.JidoTracer directly
config :jido, :observability,
  tracer: Murmur.ObsTracer
```

#### Option B: Telemetry Handler (Alternative)

Instead of wrapping the tracer, attach a `:telemetry` handler that adds OTel span attributes after AgentObs creates the span. This is more decoupled but requires lower-level OTel API calls and is harder to ensure the attributes land on the correct span.

**Recommendation: Option A** — simpler, more reliable, keeps all enrichment in one place.

### How AgentObs Maps Our Metadata to OpenInference

AgentObs's Phoenix handler translates metadata keys to OpenInference span attributes:

| Our Metadata Key | OpenInference Attribute | Phoenix UI Feature |
|---|---|---|
| `:session_id` (= workspace_id) | `session.id` | Sessions tab grouping |
| `:agent_name` | `agent.name` | Shown on spans, searchable |
| `:tags` | `tag.tags` | Filterable labels like `agent:researcher` |
| `:agent_id` (= session UUID) | `metadata` | Available in span details |
| `:model` | `llm.model_name` | Model column in traces table |

### Cross-Agent Causation: Metadata Attributes

When agent A's TellAction triggers agent B, we want to record _who triggered whom_ without nesting them in a single trace tree.

> **Note on OTel span links:** OpenTelemetry defines "span links" for expressing cross-trace relationships. However, **Arize Phoenix does not render span links in its UI** — the data is ingested but not displayed. We therefore use a simpler metadata-based approach that Phoenix _does_ show.

The approach: when `TellAction` delivers a message to agent B, include the sender's identity and trace ID in the message metadata. Agent B's tracer can then set these as span attributes on its root span:

```elixir
# In TellAction.run/2, attach causation metadata to the message:
inter_msg = %{
  id: ID.generate!(),
  role: "user",
  content: prefixed_message,
  sender_name: sender_name,
  sender_trace_id: Jido.Tracing.Context.current_trace_id()  # agent A's trace
}
```

In `Murmur.ObsTracer`, the enrichment picks up the sender info and sets searchable attributes:

```elixir
# These appear in Phoenix's span detail view as searchable metadata
metadata
|> Map.put(:triggered_by_agent, sender_name)
|> Map.put(:triggered_by_trace_id, sender_trace_id)
```

This gives developers:
- **Visibility:** see "triggered by: researcher" on agent B's trace detail
- **Navigation:** copy the `triggered_by_trace_id` value to search for agent A's trace
- **No unsupported features:** uses only standard span attributes that Phoenix renders

### What Phoenix Shows

With this setup, a developer can:

| View | What They See |
|------|---------------|
| **Sessions tab** | All sessions listed by workspace_id. Click one to see all agent traces in that workspace as a timeline |
| **Session detail** | Chat-like UI showing inputs/outputs across all agents in the workspace, ordered by time |
| **Traces tab** | All root traces. Filter by `tag.tags contains "agent:researcher"` to see one agent's traces |
| **Trace detail** | Full span tree for one agent invocation: agent → LLM → tool → LLM |
| **Search** | Search across all spans by `agent.name`, `session.id`, message content, model name |

### Caching Strategy for Metadata Lookups

The enrichment in `Murmur.ObsTracer` looks up `workspace_id` and `display_name` from the agent session. Since these are stable for the lifetime of a session, we should cache aggressively:

```elixir
# Simple ETS cache populated on agent session creation/startup
:ets.insert(:obs_session_cache, {agent_id, workspace_id, display_name})

# Lookup is O(1), no DB hit per span
:ets.lookup(:obs_session_cache, agent_id)
```

This cache can be populated in `AgentHelper.start_agent/2` when the agent process starts and cleaned up on termination.

### Implementation Phases

| Phase | Scope | Effort |
|-------|-------|--------|
| **Phase 1** | Basic workspace grouping: `session.id` = workspace_id, `agent.name` = display_name, tags. All traces for a workspace appear together in Phoenix Sessions tab. | Small — ~100 LOC wrapper module + config |
| **Phase 2** | Cross-agent causation metadata: TellAction passes sender name + trace ID to target agent. Target's root span includes `triggered_by_agent` and `triggered_by_trace_id` attributes visible in Phoenix span detail. | Small — minor changes to TellAction + tracer wrapper |
| **Phase 3** | Workspace-level dashboards: aggregate token usage, cost, and latency per workspace. Custom Phoenix annotations or Grafana dashboards consuming the same OTLP data. | Medium — mostly configuration/queries, no code changes |

### Summary

The chosen stack (AgentObs + Arize Phoenix) supports multi-agent trace grouping natively through OpenInference's `session.id` attribute and Phoenix's Sessions UI. The workspace concept maps directly to sessions — set `session.id` to the workspace UUID and all agents in that workspace are grouped together automatically.

Individual agent identity is preserved via `agent.name` and tags, allowing developers to filter down to one agent's traces within a workspace. Cross-agent causation (who triggered whom) is expressed via metadata attributes (`triggered_by_agent`, `triggered_by_trace_id`) that are visible and searchable in Phoenix's span detail view.

The only code required is a thin tracer wrapper (~100 LOC) that enriches span metadata with workspace and agent identity before delegating to `AgentObs.JidoTracer`.
