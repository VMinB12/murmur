# murmur Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-03-31

## Active Technologies
- Elixir ≥ 1.15 on OTP + Phoenix 1.8, Phoenix LiveView 1.1, Jido 2.0, Jido.AI 2.0, Jido.Action, Jido.Signal, ReqLLM, Ecto SQL 3.13, Postgrex (001-multi-agent-chat)
- PostgreSQL via Ecto (001-multi-agent-chat)
- Elixir >= 1.15 on OTP (current: Elixir 1.19.5, OTP 28.4.1) + Phoenix 1.8.5, Jido 2.0 (jido, jido_ai, jido_signal, jido_action), req_llm ~> 1.0, phoenix_live_view ~> 1.1.0 (002-modular-hex-extraction)
- PostgreSQL via Ecto SQL ~> 3.13 (Postgrex), ETS (PendingQueue, TableOwner) (002-modular-hex-extraction)
- Elixir >= 1.15 on OTP + jido ~> 2.0, jido_signal ~> 2.0, jido_action ~> 2.0, phoenix_pubsub ~> 2.0, jason ~> 1.0 (003-artifact-extraction)
- In-memory agent state (ETS), persisted via Jido checkpoint system. No Ecto/PostgreSQL dependency. (003-artifact-extraction)
- Elixir >= 1.15 on OTP + igniter ~> 0.7 (optional, runtime: false), sourceror (transitive via igniter) (004-igniter-adoption)
- N/A — install tasks modify source files, not databases (004-igniter-adoption)
- Elixir >= 1.15 on OTP + jido_signal ~> 2.0 (provides `use Jido.Signal`), uniq (UUID7, transitive), phoenix_pubsub ~> 2.0 (005-cloudevents-alignment)
- N/A — signals are ephemeral PubSub messages (005-cloudevents-alignment)
- Elixir >= 1.15 on OTP + phoenix_pubsub ~> 2.0, telemetry ~> 1.0 (already in tree), ecto_sql (for jido_tasks context) (006-platform-improvements)
- PostgreSQL via Ecto SQL (jido_tasks context module) (006-platform-improvements)
- Elixir ≥ 1.15 on OTP + `opentelemetry_api ~> 1.5`, `req_llm ~> 1.0`, `agent_obs ~> 0.1.4`, `:telemetry ~> 1.3` (007-llm-otel-tracing)
- ETS (in-memory span context), no database changes (007-llm-otel-tracing)
- Elixir ≥ 1.15 on OTP + Jido 2.0 (agent framework), Jido.AI (LLM), Ecto SQL + Postgrex (database), Phoenix LiveView 1.1 (008-sql-agent-plugin)
- PostgreSQL via Ecto for both the app database (Murmur.Repo) and a separate SQL agent target database (JidoSql.Repo) (008-sql-agent-plugin)

- Elixir ≥ 1.15 on OTP + Phoenix 1.8, Phoenix LiveView 1.1, Jido 2.0, Ecto SQL 3.13, Postgrex (001-multi-agent-chat)

## Project Structure

```text
src/
tests/
```

## Commands

# Add commands for Elixir ≥ 1.15 on OTP

## Code Style

Elixir ≥ 1.15 on OTP: Follow standard conventions

## Recent Changes
- 008-sql-agent-plugin: Added Elixir ≥ 1.15 on OTP + Jido 2.0 (agent framework), Jido.AI (LLM), Ecto SQL + Postgrex (database), Phoenix LiveView 1.1
- 007-llm-otel-tracing: Added Elixir ≥ 1.15 on OTP + `opentelemetry_api ~> 1.5`, `req_llm ~> 1.0`, `agent_obs ~> 0.1.4`, `:telemetry ~> 1.3`
- 006-platform-improvements: Added Elixir >= 1.15 on OTP + phoenix_pubsub ~> 2.0, telemetry ~> 1.0 (already in tree), ecto_sql (for jido_tasks context)


<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
