# Quickstart: LLM OpenTelemetry Tracing

**Feature Branch**: `007-llm-otel-tracing`  
**Date**: 2026-03-30

## Prerequisites

- Elixir ≥ 1.15, OTP installed
- Docker (for Arize Phoenix)
- Running PostgreSQL instance

## Setup

### 1. Start Arize Phoenix

```bash
docker compose up -d phoenix
```

Or standalone:
```bash
docker run -d -p 6006:6006 -p 4317:4317 arizephoenix/phoenix:latest
```

### 2. Enable raw telemetry payloads

In `config/config.exs` (or `config/dev.exs`):
```elixir
config :req_llm, telemetry: [payloads: :raw]
```

### 3. Start the application

```bash
mix phx.server
```

The `ReqLLMTracer` attaches automatically during application boot.

### 4. Trigger an agent conversation

Open the frontend and send a message to any agent (e.g., "Hello, who are you?").

### 5. View traces

Open [http://localhost:6006](http://localhost:6006) in your browser. You should see:
- An "LLM {model_name}" trace for each LLM call
- Click a trace to see input messages (with roles), output messages, token counts
- Tool calls visible when agents use tools

## Verification Checklist

- [ ] Trace appears in Phoenix with span kind "LLM"
- [ ] Input messages show role and content for each message
- [ ] Output messages show the assistant response
- [ ] Token counts (prompt, completion, total) are populated
- [ ] Tool calls appear when agent uses tools
- [ ] Multiple conversations show different session IDs
- [ ] Agent name is visible on traces

## Configuration

| Config | Default | Description |
|--------|---------|-------------|
| `config :req_llm, telemetry: [payloads: :raw]` | `:none` | Enable full message content in telemetry |
| `config :opentelemetry_exporter, otlp_endpoint:` | `http://localhost:6006` | Phoenix OTLP endpoint |
| `config :opentelemetry_exporter, otlp_protocol:` | `:http_protobuf` | OTLP protocol |
| `config :agent_obs, enabled:` | `true` | Enable/disable all observability |

## Disabling in Production

To disable raw payloads in production (reduces memory overhead):

```elixir
# config/prod.exs
config :req_llm, telemetry: [payloads: :none]
```

Traces will still be created with model name, token counts, and latency — but without message content.

## Running Tests

```bash
mix test apps/jido_murmur/test/jido_murmur/telemetry/req_llm_tracer_test.exs
```
