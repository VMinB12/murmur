# Research: Frontend Architecture Review

## Objective

Evaluate the current frontend architecture of `jido_murmur_web` (reusable component library) and `murmur_demo` (reference application) across four dimensions:

1. **DaisyUI utilization** — Are we leveraging DaisyUI fully, or underusing it?
2. **Component library alternatives** — Should we consider SaladUI or similar?
3. **LLM token streaming patterns** — Are we using LiveView streams? Best practices?
4. **Separation of concerns** — Is `jido_murmur_web` free of agent-specific logic?

---

## 1. DaisyUI Utilization

### Current Setup

- **daisyUI v4** is installed as a Tailwind CSS plugin via vendored JS in `murmur_demo/assets/vendor/daisyui.js`
- Two custom themes (light/dark) configured via `daisyui-theme.js` plugin with oklch color variables
- Import syntax follows Tailwind v4 conventions: `@plugin "../vendor/daisyui"`

### DaisyUI Components Currently Used

| Component Class | Where Used |
|----------------|-----------|
| `btn`, `btn-primary`, `btn-ghost`, `btn-xs`, `btn-sm`, `btn-soft` | core_components.ex, templates |
| `input`, `input-bordered`, `input-error` | core_components.ex |
| `select`, `select-bordered`, `select-error` | core_components.ex |
| `textarea`, `textarea-error` | core_components.ex |
| `checkbox`, `checkbox-sm` | core_components.ex |
| `modal`, `modal-box`, `modal-action`, `modal-backdrop` | workspace_live.html.heex |
| `alert`, `alert-info`, `alert-error` | core_components.ex (flash) |
| `toast`, `toast-top`, `toast-end` | core_components.ex (flash) |
| `table`, `table-zebra` | core_components.ex |
| `loading`, `loading-dots`, `loading-spinner`, `loading-xs` | templates, chat_stream.ex |
| `badge` | limited usage |
| `fieldset`, `label` | core_components.ex |

### DaisyUI Components NOT Used (Opportunities)

| Component | Potential Use |
|-----------|--------------|
| `drawer` | Workspace sidebar, mobile navigation |
| `dropdown` | Agent profile selector, artifact type picker |
| `collapse` / `accordion` | Thinking traces, tool call details (currently using raw `<details>`) |
| `card` | Message bubbles, artifact cards, task cards |
| `tabs` | Artifact panel tabs (currently manual), view mode toggle |
| `tooltip` | Usage stats (currently custom hover), agent status |
| `avatar` | Agent avatars in chat |
| `chat` / `chat-bubble` | **daisyUI has a native chat bubble component** — not used at all |
| `skeleton` | Loading states |
| `progress` | Streaming progress, task completion |
| `stat` | Token usage display, workspace metrics |
| `swap` | View mode toggle (split/unified) |
| `menu` | Workspace list, context menus |
| `indicator` | Unread message badges, agent status |
| `kbd` | Keyboard shortcuts display |
| `diff` | Before/after comparisons |
| `timeline` | Unified view message timeline |

### Assessment

**DaisyUI is partially utilized.** The core form components (inputs, buttons, modals) leverage daisyUI well, but the chat interface itself uses raw Tailwind classes instead of daisyUI's `chat`, `chat-bubble`, `avatar`, and `card` components. Collapsible sections use native `<details>` instead of daisyUI `collapse`. The artifact panel uses hand-rolled tabs instead of daisyUI `tabs`.

**Key gap:** daisyUI ships a purpose-built `chat` component (`chat chat-start`, `chat-bubble`, `chat-header`, `chat-footer`, `chat-image`) that maps almost perfectly to the multi-agent chat use case. It's unused.

---

## 2. Component Library Alternatives: SaladUI et al.

### Options Considered

| Library | Type | Approach | Elixir-Native? |
|---------|------|----------|---------------|
| **daisyUI** (current) | CSS plugin | Tailwind class-based, no JS | No (CSS only) |
| **SaladUI** | LiveView components | shadcn/ui port for Phoenix, copy-paste components | Yes |
| **Petal Components** | LiveView components | Pre-built Phoenix components with Tailwind | Yes |
| **Surface UI** | LiveView DSL | Component-oriented framework, alternative syntax | Yes |
| **Live Svelte** | Svelte bridge | Embed Svelte components in LiveView | Hybrid |
| **Custom (status quo)** | Hand-rolled | Raw Tailwind + daisyUI classes in HEEx | Yes |

### Analysis

#### SaladUI
- **Pros**: shadcn/ui-quality components, copy-paste model (own the code), rich components (Dialog, Command, Sheet, Popover, Table, etc.), actively maintained, growing community
- **Cons**: Adds a dependency pattern, not all components may be needed, styling may conflict with daisyUI's semantic classes, shadcn aesthetic may not match the Elixir/dark theme we've built

#### Petal Components
- **Pros**: Purpose-built for Phoenix, mature, comprehensive
- **Cons**: Heavier dependency, opinionated styling, less flexible than composition-first approach

#### Keep daisyUI + Custom
- **Pros**: Already integrated, semantic class names reduce template complexity, theming system works well, zero JS dependency, lightweight
- **Cons**: Limited interactive components (no command palette, no sheet/popover), some components feel basic compared to shadcn

### Recommendation

**Keep daisyUI as the foundation but use it more fully.** The current setup is sound — daisyUI provides semantic CSS classes with no JS overhead, which aligns with LiveView's server-rendered philosophy. Switching to SaladUI would be a significant migration with marginal benefit.

**However**, if we need rich interactive components (command palette, sheet panels, complex popovers), SaladUI could supplement daisyUI for specific high-value components. This would be an additive approach, not a replacement.

**Action items:**
- Adopt daisyUI's `chat`/`chat-bubble` components for message rendering
- Use `collapse`/`accordion` for thinking/tool-call sections
- Use `tabs` for the artifact panel
- Use `dropdown` for agent selection instead of modal
- Use `card` for agent columns, task cards, artifact cards
- Evaluate SaladUI only if a specific component need arises that daisyUI can't satisfy

---

## 3. LLM Token Streaming Patterns

### Current Implementation

**Architecture:** Agent → `StreamingPlugin` → PubSub broadcast → LiveView `handle_info` → assign update → template re-render

**Storage pattern:** Messages are stored as a **plain Elixir map of lists** in assigns:
```elixir
assign(:messages, %{session_id => [msg1, msg2, ...]})
assign(:streaming, %{session_id => %{content: "", thinking: "", tool_calls: [], usage: nil}})
```

**Template rendering:** Direct `for` comprehension over the list:
```heex
<%= for msg <- Map.get(@messages, session.id, []) do %>
  <div id={"msg-#{msg.id}"}>...</div>
<% end %>
```

**Token accumulation:** String concatenation in `update_streaming/4`:
```elixir
defp update_streaming(socket, session_id, field, delta) do
  update(socket, :streaming, fn streams ->
    Map.update(streams, session_id, ..., fn s ->
      Map.update(s, field, delta, &(&1 <> delta))
    end)
  end)
end
```

### LiveView Streams — Are They Used?

**No.** Neither `stream/3`, `@streams`, nor `phx-update="stream"` appear anywhere in the codebase. Messages are stored as regular list assigns.

### Should LiveView Streams Be Used?

This is nuanced. Let's evaluate against the two data types:

#### For Message History (`@messages`)
- **Pro streams:** Messages are an append-only collection that grows over time. LiveView streams would avoid re-rendering the entire message list on each new message. As conversations grow to 50+ messages, the current approach re-diffs the entire DOM tree on every update.
- **Pro streams:** Memory efficiency — streams don't hold the full collection in the socket's process memory. With multiple agents, message lists can grow large.
- **Con streams:** Messages are stored per-session in a nested map (`%{session_id => [msgs]}`). LiveView streams don't natively support this nested structure — you'd need one stream per agent session, which means dynamic stream names.
- **Con streams:** On `murmur.message.completed`, the code reloads full history from agent state (`load_messages_for_session/1`) and replaces the entire list. This pattern would need `reset: true` on streams.
- **Con streams:** Unified view flattens messages across all sessions into a timeline. Streams can't be merged/sorted across stream collections.

**Verdict:** Streams would help for split-view (each agent column is an independent append-only list). For unified view, streams are harder. A hybrid approach is possible but adds complexity.

#### For Streaming Tokens (`@streaming`)
- Token-by-token updates are the most frequent UI updates (potentially hundreds per second per agent)
- The current approach re-renders the streaming content on every token. This is **small diffs** (appending a few characters) so LiveView's diff engine handles it well
- LiveView streams are designed for **collections of discrete items**, not string accumulation. Tokens are not a "list of items" — they're incremental string appends
- The `@streaming` assign with string concatenation is actually the **correct pattern** for this use case

**Verdict:** LiveView streams are NOT the right tool for token-by-token accumulation. The current string-append pattern is correct.

### Performance Concerns

The main performance concern is **message re-rendering**, not token streaming:

1. **Full message list re-render:** Every time a new message arrives, the entire `for msg <- @messages[session_id]` loop re-evaluates. LiveView's diff engine mitigates this (unchanged elements produce minimal diffs), but the server still walks the full list.

2. **Message completion reload:** `handle_info(:murmur.message.completed)` calls `load_messages_for_session/1` which loads the entire thread from agent state, replacing the local list. This is O(n) on every message completion.

3. **Unified timeline sort:** `unified_timeline/2` flat-maps and sorts all messages across all sessions on every render. This is O(n log n) per render cycle.

### Recommendations

| Issue | Recommendation | Priority |
|-------|---------------|----------|
| Messages as plain lists | Migrate to LiveView streams (one stream per agent session) in split view | Medium |
| Unified timeline sorting | Cache the sorted timeline as an assign, update incrementally | Medium |
| Token streaming pattern | **Keep current approach** — string append is correct for this use case | N/A (already good) |
| Auto-scroll via MutationObserver | Consider `phx-hook` with `updated()` callback instead (more efficient) | Low |
| Tool call tracking in streaming | Current approach is fine — small list, infrequent updates | N/A |

---

## 4. Separation of Concerns: Agent-Specific Logic

### Principle

Per the architecture docs, `jido_murmur_web` is a **generic** multi-agent LiveView component library. It should contain no agent-specific logic (arxiv, sql, etc.). Agent-specific UI should live in the consuming application (`murmur_demo`) or in the agent's own package.

### Findings in jido_murmur_web

#### Issue 1: ArXiv-specific artifact renderers shipped as defaults

**File:** `jido_murmur_web/lib/jido_murmur_web/components/artifact_panel.ex`
```elixir
@default_renderers %{
  "papers" => PaperList,        # ArXiv-specific
  "displayed_paper" => PdfViewer # ArXiv-specific
}
```

**Files:**
- `jido_murmur_web/lib/jido_murmur_web/components/artifact_panel/paper_list.ex` — Renders arxiv papers with fields `id`, `title`, `abstract`, `published`, `url`, `pdf_url`
- `jido_murmur_web/lib/jido_murmur_web/components/artifact_panel/pdf_viewer.ex` — Renders PDF in iframe

**Problem:** These are arxiv-specific renderers baked into the generic library. A consumer who doesn't use arxiv gets these as default renderers. The `PaperList` component assumes an arxiv paper data shape.

**Severity:** Medium. The renderer registry is pluggable (consumers can override), but the defaults leak domain-specific knowledge into the generic library.

#### Issue 2: No other agent-specific code in jido_murmur_web

The remaining components (`ChatMessage`, `ChatStream`, `MessageInput`, `AgentHeader`, `AgentSelector`, `WorkspaceList`, `StreamingIndicator`) are fully generic. Good.

### Findings in murmur_demo

#### Issue 3: SQL query re-execution hardcoded in WorkspaceLive

**File:** `murmur_demo/lib/murmur_web/live/workspace_live.ex` (lines 195-220)
```elixir
def handle_event("reexecute_query", %{"session-id" => session_id, "sql" => sql, "index" => index_str}, socket) do
  case JidoSql.QueryExecutor.execute(JidoSql.Repo, sql) do
    {:ok, result} -> {"loaded_result", result}
    {:error, msg} -> {"loaded_error", msg}
  end
  # ...updates artifacts...
end
```

**Problem:** `WorkspaceLive` directly imports and calls `JidoSql.QueryExecutor.execute/2` with a hardcoded `JidoSql.Repo`. This couples the generic workspace LiveView to the SQL agent package. If `jido_sql` is not in the deps, this compile-fails.

**Severity:** High. This is the most significant violation — the main orchestrator LiveView has a hard dependency on a specific agent package.

#### Issue 4: Demo artifact dispatcher hardcodes agent-specific routing

**File:** `murmur_demo/lib/murmur_web/components/artifacts.ex`
```elixir
def artifact_badge(%{name: "sql_results"} = assigns) do
  ~H"<SqlResults.badge ... />"
end
```

**Problem:** The artifact dispatcher pattern-matches on `"sql_results"` directly. This is acceptable in the demo app (it's the demo's job to configure agent-specific renderers), but ideally should use the same pluggable registry pattern as `jido_murmur_web`'s `ArtifactPanel`.

**Severity:** Low. This is in the demo app, which is supposed to be opinionated. But it duplicates the dispatcher pattern instead of using `ArtifactPanel`'s renderer registry.

#### Issue 5: murmur_demo has its own copy of paper_list.ex and pdf_viewer.ex

**Files:**
- `murmur_demo/lib/murmur_web/components/artifacts/paper_list.ex`
- `murmur_demo/lib/murmur_web/components/artifacts/pdf_viewer.ex`

These are duplicates of the same components in `jido_murmur_web`. The demo app should either import from `jido_murmur_web` or have its own versions — but having both creates maintenance burden.

**Severity:** Low-Medium. Code duplication risk.

### Summary of Separation Issues

| Issue | Location | Severity | Recommendation |
|-------|----------|----------|----------------|
| ArXiv renderers as defaults in generic lib | `jido_murmur_web/artifact_panel.ex` | Medium | Move to `jido_arxiv` or make `@default_renderers` empty |
| SQL re-execution in WorkspaceLive | `murmur_demo/workspace_live.ex` | High | Extract to callback/hook pattern or move to `jido_sql` |
| Hardcoded artifact routing in demo | `murmur_demo/artifacts.ex` | Low | Use `ArtifactPanel` renderer registry consistently |
| Duplicate paper/pdf components | murmur_demo duplicates jido_murmur_web | Low-Med | Import from jido_murmur_web or remove duplicates |

---

## 5. Additional Observations

### workspace_live.ex Complexity

The main LiveView is ~900 lines handling:
- Agent lifecycle (add, remove, clear, start, stop)
- Message handling (send, receive, display)
- Token streaming (delta, response, tool calls, usage)
- Artifact management (receive, display, tab switching)
- Task board (create, update, toggle)
- View mode switching (split/unified)
- SQL query re-execution

This is a monolithic LiveView. Consider extracting concerns into:
- A streaming handler module (token accumulation, usage merging)
- An artifact handler module
- A task board handler module

### Template Size

`workspace_live.html.heex` is large (400+ lines) with two complete view modes (split and unified). Extracting components for the split and unified views would improve maintainability.

### Missing Loading States

When conversations load from storage (`load_messages_for_session`), there's no loading skeleton or indicator. DaisyUI's `skeleton` component could improve UX here.

### No Keyboard Navigation

The chat interface lacks keyboard shortcuts beyond Enter-to-send. No command palette, no Ctrl+K search, no arrow-key navigation between agents.

---

## References

- [jido_murmur_web architecture](../../Architecture/jido-murmur-web.md)
- [murmur_demo architecture](../../Architecture/murmur-demo.md)
- [daisyUI v4 documentation](https://daisyui.com/components/)
- [SaladUI GitHub](https://github.com/bluzky/salad_ui)
- [LiveView streams docs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#stream/4)
