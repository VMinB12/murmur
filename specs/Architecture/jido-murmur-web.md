# jido_murmur_web — LiveView Component Library

## Purpose

Pre-built Phoenix LiveView component library providing drop-in UI building blocks for the multi-agent chat platform. Components can be imported directly or copied via a mix generator for full customization.

## Public API

### Component Registry

```elixir
import JidoMurmurWeb.Components  # imports all 10 component functions
```

### Components

| Component | Function | Purpose |
|-----------|----------|---------|
| `ChatMessage` | `chat_message/1` | Completed message bubble with thinking trace, tool calls, usage stats |
| `ChatStream` | `chat_stream/1` | In-flight streaming state: thinking, tool calls, token-by-token content |
| `MessageInput` | `message_input/1` | Auto-resizing textarea with Enter-to-send keyboard shortcut |
| `StreamingIndicator` | `streaming_indicator/1` | Animated dot indicator showing agent busy/idle status |
| `AgentHeader` | `agent_header/1` | Column header with agent name, color dot, status, remove button |
| `AgentSelector` | `agent_selector/1` | Modal for adding agents: profile dropdown + name input |
| `WorkspaceList` | `workspace_list/1` | Sidebar navigation list of workspaces |
| `ArtifactPanel` | `artifact_panel/1` | Tabbed side panel for artifacts with badge + detail dispatching |
| `ArtifactPanel.Generic` | `badge/1`, `detail/1` | Fallback renderer for unknown artifact types |
| `ArtifactPanel.PaperList` | `badge/1`, `detail/1` | arXiv paper list renderer |
| `ArtifactPanel.PdfViewer` | `badge/1`, `detail/1` | Single PDF viewer renderer |

## Design Patterns

### Stateless Function Components

All components are stateless `Phoenix.Component` functions — no LiveComponent complexity. Templates use HEEx with Tailwind CSS classes.

### Event Delegation

Components accept event name attributes (`on_submit`, `on_remove`) for customization. Events are dispatched to the parent LiveView via standard `phx-click`/`phx-submit` attributes.

### Renderer Registry (ArtifactPanel)

```elixir
@default_renderers %{
  "papers" => PaperList,
  "displayed_paper" => PdfViewer
}
```

Renderers passed via the `renderers` assign override/extend defaults. The dispatcher looks up the renderer by artifact type and delegates to `badge/1` or `detail/1`.

### Color Customization

Components accept optional `color` maps with `:dot`, `:header`, `:text`, `:bg` keys for per-agent styling.

## JavaScript Hooks

| Hook | Element | Behavior |
|------|---------|----------|
| `.ChatInput` (colocated) | Message textarea | Auto-resize on input, submit on Enter, reset after send |

## Installation

```bash
# Copy all components into your project (customization mode)
mix jido_murmur_web.install all

# Or selective groups:
mix jido_murmur_web.install chat        # ChatMessage, ChatStream, MessageInput, StreamingIndicator
mix jido_murmur_web.install workspace   # WorkspaceList, AgentSelector, AgentHeader
mix jido_murmur_web.install artifacts   # ArtifactPanel + renderers
```

Uses Igniter for idempotent code generation with namespace substitution.

## Dependencies

**Requires:** `jido_murmur`, `phoenix_live_view ~> 1.1.0`, `phoenix_html ~> 4.1`, `jason ~> 1.2`

**Used by:** `murmur_demo` (and any consuming Phoenix app)

## Configuration

No required config. Optional Tailwind source directive in consuming app's `app.css`:

```css
@source "../../../deps/jido_murmur_web";
```
