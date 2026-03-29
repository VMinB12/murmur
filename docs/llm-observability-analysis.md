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
