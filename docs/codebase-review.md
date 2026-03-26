# Murmur Codebase Review — Prioritized Recommendations

## Priority 1: Correctness & Reliability

### 1.1 Migrate `@messages` to LiveView streams

**Impact**: Memory leak / process crash under load
**Effort**: Medium

Every message ever sent lives in the LiveView process memory as a plain list in a map. With active agents producing long conversations, this will balloon memory and eventually crash the LiveView process.

**Current** (`workspace_live.ex`):
```elixir
|> assign(:messages, messages_map)            # map of session_id => [msg, ...]
|> update(:messages, fn msgs ->
  Map.update(msgs, session_id, [user_msg], &(&1 ++ [user_msg]))
end)
```

**Target**: Use `stream/3` per agent session. Since you have multiple independent message lists (one per agent), you can use a single stream with composite DOM IDs, or manage per-session streams with dynamic stream names.

Key considerations:
- Unified timeline view will need to re-stream from DB rather than reading assigns
- Empty state detection needs a separate `@messages_empty?` assign per session
- The `load_messages_for_session/1` call already fetches from storage, so streaming is a natural fit

---

### 1.2 Supervise ETS table ownership

**Impact**: Data loss on crash
**Effort**: Low

`PendingQueue.init()` and `Runner.init()` create ETS tables as side effects in `Application.start/2`. If the owning process dies, the tables vanish with no recovery.

**Fix**: Create a small GenServer that owns the tables and add it to the supervision tree:

```elixir
defmodule Murmur.Agents.TableOwner do
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    :ets.new(:murmur_pending_messages, [:named_table, :public, :duplicate_bag])
    :ets.new(:murmur_active_runners, [:set, :public, :named_table])
    {:ok, :ok}
  end
end
```

Then add `Murmur.Agents.TableOwner` to the children list in `application.ex` **before** `Murmur.Jido`.

---

### 1.3 Fix unified timeline sort order — mixed UUID versions

**Impact**: Messages display in wrong order in unified view
**Effort**: Low

Jido internally uses **UUIDv7** (time-ordered) for thread entry IDs via `Jido.Signal.ID.generate!()`. However, the 7 call sites in Murmur's own code (`workspace_live.ex`, `tell_action.ex`, `ui_turn.ex`) use `Ecto.UUID.generate()` which produces **UUIDv4** (random). When `unified_timeline/2` sorts by `&1.id`, the v4 IDs land in arbitrary positions among the v7 ones.

**Fix**: Replace all `Ecto.UUID.generate()` calls with `Jido.Signal.ID.generate!()` so every message ID is UUIDv7 and time-sortable:

```elixir
# In workspace_live.ex, tell_action.ex, ui_turn.ex — replace all occurrences of:
id: Ecto.UUID.generate()

# With:
id: Jido.Signal.ID.generate!()
```

Files to update:
- `lib/murmur_web/live/workspace_live.ex` (4 sites)
- `lib/murmur/agents/tell_action.ex` (1 site)
- `lib/murmur/agents/ui_turn.ex` (2 sites — fallback IDs)

---

### 1.4 Remove deprecated `compilers` key in `mix.exs`

**Impact**: Deprecation warning / future breakage
**Effort**: Trivial

```elixir
# Remove this line from project/0:
compilers: [:phoenix_live_view] ++ Mix.compilers(),
```

`Mix.compilers/0` returns `[]` in modern Elixir and the `:phoenix_live_view` compiler is auto-registered.

---

## Priority 2: Robustness & Observability

### 2.1 Add Oban for background job processing

**Impact**: Reliability of LLM calls across restarts
**Effort**: Medium

The current `Runner` uses ETS + `Task.Supervisor` for async LLM work. If the node restarts, all in-flight messages are lost. [Oban](https://hex.pm/packages/oban) provides:

- **Persistence**: Jobs survive restarts (Postgres-backed)
- **Rate limiting**: Protect against LLM API cost spikes
- **Retries with backoff**: Failed LLM calls auto-retry
- **Observability**: Job status visible in LiveDashboard via `oban_web`
- **Unique jobs**: Prevent duplicate asks for the same session

```elixir
# mix.exs
{:oban, "~> 2.18"}

# config.exs
config :murmur, Oban,
  repo: Murmur.Repo,
  queues: [llm: 10]
```

This would replace the `Runner` drain-loop + ETS active-runner tracking entirely.

---

### 2.2 Add Sobelow for security static analysis

**Impact**: Catch security issues early
**Effort**: Trivial

```elixir
# mix.exs
{:sobelow, "~> 0.13", only: [:dev, :test], runtime: false}
```

Add to precommit alias:
```elixir
precommit: [
  "compile --warnings-as-errors",
  "deps.unlock --unused",
  "format",
  "test",
  "credo --strict",
  "sobelow --config"   # add this
]
```

---

### 2.3 Stop swallowing exceptions silently

**Impact**: Debugging difficulty
**Effort**: Trivial

In `cleanup_storage/1`:
```elixir
# Current — hides all errors
rescue
  _ -> :ok

# Better
rescue
  e ->
    Logger.warning("Failed to cleanup storage for session #{session.id}: #{Exception.message(e)}")
    :ok
```

Similarly in `Agents.Telemetry.detach/1`.

---

## Priority 3: Code Quality & Ecosystem Alignment

### 3.1 Use `Ecto.Enum` for status fields

**Impact**: Type safety, cleaner code
**Effort**: Low

In `AgentSession`:
```elixir
# Current
field :status, :string, default: "idle"
|> validate_inclusion(:status, ["idle", "busy"])

# Better
field :status, Ecto.Enum, values: [:idle, :busy], default: :idle
```

This gives you atom comparisons everywhere instead of string matching, and invalid values fail at the Ecto layer.

---

### 3.2 Add MDEx for Markdown rendering

**Impact**: Much better UX for agent responses
**Effort**: Low–Medium

Agent responses (especially from `code_agent`) contain Markdown with code blocks, but they render as plain text. [MDEx](https://hex.pm/packages/mdex) is a fast Rust NIF for Markdown→HTML:

```elixir
{:mdex, "~> 0.4"}
```

Then in the template, render `{raw(MDEx.to_html!(msg.content))}` for assistant messages. Add syntax highlighting with the built-in options.

---

### 3.3 Add Styler as a formatter plugin

**Impact**: Consistent code style without manual effort
**Effort**: Trivial

```elixir
# mix.exs
{:styler, "~> 1.0", only: [:dev, :test], runtime: false}

# .formatter.exs
[
  plugins: [Phoenix.LiveView.HTMLFormatter, Styler],
  ...
]
```

Auto-fixes: unused aliases, pipe chain style, module attribute ordering, `with` clause formatting, etc.

---

### 3.4 Centralize agent color/metadata mapping

**Impact**: Maintainability
**Effort**: Low

Colors are duplicated across `Catalog`, `agent_header_class/1`, `agent_dot_class/1`, and `agent_color/2`. Consolidate into `Catalog`:

```elixir
# In Catalog
@profiles %{
  "general_agent" => {
    Murmur.Agents.Profiles.GeneralAgent,
    %{description: "...", color: "blue", css_dot: "bg-blue-500", css_header: "border-blue-500/20 bg-blue-500/5"}
  },
  ...
}
```

Then `WorkspaceLive` calls `Catalog.get_profile!(id)` for all styling needs.

---

### 3.5 Add Hammer for LLM rate limiting

**Impact**: Cost protection
**Effort**: Low

Your inter-agent `TellAction` has a 5-hop depth limit, but there's no rate limit on user messages or total LLM calls per time window.

```elixir
{:hammer, "~> 6.2"}
```

```elixir
case Hammer.check_rate("llm:#{session_id}", 60_000, 30) do
  {:allow, _} -> Runner.send_message(session, content)
  {:deny, _} -> put_flash(socket, :error, "Rate limit reached. Please wait.")
end
```

---

## Priority 4: Nice to Have

### 4.1 Phoenix.Presence for agent status tracking

Replace manual `@agent_statuses` map with `Phoenix.Presence` for distributed-safe, self-cleaning presence tracking. Most valuable if you plan to run multiple nodes.

### 4.2 Req.Test for HTTP-level LLM testing

You already have Mox for the behaviour, but `Req.Test` (ships with `:req`) can intercept at the HTTP layer for more realistic integration tests without hitting real APIs.

### 4.3 Flop for workspace list pagination

Not urgent now, but if workspaces grow, `Flop`/`Flop.Phoenix` gives declarative filter/sort/pagination with LiveView integration.

### 4.4 Remove unused Swoosh dependency

`Murmur.Mailer` exists but is never called. If email isn't planned, removing Swoosh eliminates dead code and two supervision tree entries.

---

## Summary Table

| # | Change | Priority | Effort | Category |
|---|--------|----------|--------|----------|
| 1.1 | LiveView streams for messages | P1 | Medium | Memory safety |
| 1.2 | Supervise ETS tables | P1 | Low | Crash resilience |
| 1.3 | Fix unified timeline sorting | P1 | Low | Correctness |
| 1.4 | Remove deprecated `compilers` | P1 | Trivial | Hygiene | ✅ |
| 2.1 | Oban for background jobs | P2 | Medium | Reliability |
| 2.2 | Sobelow security analysis | P2 | Trivial | Security | ✅ |
| 2.3 | Log instead of swallowing exceptions | P2 | Trivial | Observability | ✅ |
| 3.1 | Ecto.Enum for status | P3 | Low | Type safety |
| 3.2 | MDEx for Markdown rendering | P3 | Low–Med | UX |
| 3.3 | Styler formatter plugin | P3 | Trivial | Code quality |
| 3.4 | Centralize color mapping | P3 | Low | Maintainability |
| 3.5 | Hammer rate limiting | P3 | Low | Cost protection |
| 4.1 | Phoenix.Presence | P4 | Medium | Scalability |
| 4.2 | Req.Test | P4 | Low | Testing |
| 4.3 | Flop pagination | P4 | Low | UX |
| 4.4 | Remove unused Swoosh | P4 | Trivial | Hygiene | ✅ |
