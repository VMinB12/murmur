# Artifact Panel UI Architecture

## Layout

The workspace view is divided into two main areas:

```
┌──────────────────────────────────────────────────────────────────┐
│ Workspace Header                                          [+Add] │
├─────────────────────────────────┬────────────────────────────────┤
│                                 │                                │
│  Chat Area                      │  Artifact Panel (toggleable)   │
│  (split columns or unified)     │                                │
│                                 │  ┌──────────────────────────┐  │
│  ┌──────────┐ ┌──────────┐     │  │ Tab bar:                 │  │
│  │ Agent A   │ │ Agent B   │    │  │  [Agent A / papers]      │  │
│  │ messages  │ │ messages  │    │  │  [Agent B / query_results]│  │
│  │           │ │           │    │  └──────────────────────────┘  │
│  │ [📄 3]    │ │ [📊 1]    │    │  ┌──────────────────────────┐  │
│  │           │ │           │    │  │                          │  │
│  │ [input]   │ │ [input]   │    │  │  Full artifact renderer  │  │
│  └───────────┘ └───────────┘    │  │  (PDF, table, cards...)  │  │
│                                 │  │                          │  │
│                                 │  └──────────────────────────┘  │
└─────────────────────────────────┴────────────────────────────────┘
```

**Chat column**: Shows compact **artifact badges** — clickable chips like
`📄 3 papers` inline below the messages. Clicking a badge opens the right
panel focused on that artifact.

**Artifact panel**: A full-height right panel that renders one artifact at a
time at full size. Tabs across the top let you switch between all active
artifacts from any agent. The panel opens when a badge is clicked and can be
closed with a button. Works identically in both split and unified mode.

## Component structure

```
lib/murmur_web/components/
  artifacts.ex                     # Dispatcher: badge/1 and detail/1
  artifacts/
    paper_list.ex                  # Papers card grid
    pdf_viewer.ex                  # Iframe PDF viewer
    generic.ex                     # JSON/list fallback for unknown types
```

Each renderer module exposes two function components:

- **`badge/1`** — compact indicator for the chat column badge strip.
  Receives: `name`, `data`, `session_id`.
- **`detail/1`** — full artifact renderer for the detail panel.
  Receives: `name`, `data`, `session_id`.

The dispatcher in `artifacts.ex` pattern-matches on the artifact `name` and
delegates to the correct renderer. Adding a new artifact type requires one
new module and one clause in the dispatcher — no template changes.

## LiveView state

```elixir
@artifacts          # %{session_id => %{"papers" => [...], "displayed_paper" => %{...}}}
@active_artifact    # nil | %{session_id: "...", name: "papers"}
```

- Clicking a badge fires `"open_artifact"` with the session_id and name.
- The panel close button fires `"close_artifact"`.
- The panel reads data from `@artifacts[@active_artifact.session_id][@active_artifact.name]`.
- Tab list is computed from all non-empty entries across all sessions in `@artifacts`.

## Artifact types

### `"papers"` (paper_list.ex)

Emitted by the ArxivSearch tool in `:append` mode. Data is a list of paper
maps with fields: `id`, `title`, `abstract`, `published`, `url`, `pdf_url`.

- **Badge**: `📄 N papers`
- **Detail**: Scrollable card list with title, abstract excerpt, date,
  and PDF link per paper.

### `"displayed_paper"` (pdf_viewer.ex)

Emitted by the DisplayPaper tool in `:replace` mode. Data is a single map
with: `id`, `title`, `url`, `pdf_url`.

- **Badge**: `📑 Viewing: <title>`
- **Detail**: Full-height iframe rendering the PDF, with link to open
  externally.

### Fallback (generic.ex)

Any artifact name not matched by a specific renderer falls through to the
generic component which renders lists as numbered items and maps as pretty
JSON.

## Adding a new artifact type

1. Create `lib/murmur_web/components/artifacts/my_type.ex` with `badge/1`
   and `detail/1`.
2. Add a clause in `MurmurWeb.Components.Artifacts.badge/1` and `detail/1`
   that delegates to it.
3. From the tool action, call `Artifact.emit(ctx, "my_type", data)`.

No template editing required.
