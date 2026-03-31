# Goals

## Success Metrics

| Metric | Target | How Measured |
|--------|--------|-------------|
| Core packages published to Hex | `jido_murmur`, `jido_murmur_web`, `jido_tasks`, `jido_arxiv` | Hex.pm listing |
| Test coverage per package | ≥ 80% | `mix test --cover` |
| Agent-to-agent round-trip latency | < 500ms | PubSub event timing in tests |
| Conversation hibernate/thaw reliability | 100% data integrity | Integration tests |
| SQL agent query safety | Zero write operations in default mode | Guard tests |

## Milestones

| Milestone | Description | Target Date | Status |
|-----------|-------------|-------------|--------|
| M1: Core multi-agent chat | Workspaces, agents, streaming, persistence | — | In progress |
| M2: Hex package extraction | Independent packages with public APIs | — | Planned |
| M3: Artifact system extraction | Standalone artifact package | — | Planned |
| M4: SQL agent plugin | Natural-language SQL with safety guardrails | — | In progress |
| M5: Platform hardening | CloudEvents alignment, OTel tracing, Igniter install tasks | — | Planned |
