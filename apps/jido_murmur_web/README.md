# JidoMurmurWeb

Pre-built [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view) components for [jido_murmur](https://github.com/agentjido/jido_murmur) multi-agent chat interfaces. Drop-in UI building blocks or copy them for full customization via the install generator.

## Installation

Add `jido_murmur_web` to your dependencies (requires `jido_murmur`):

```elixir
def deps do
  [
    {:jido_murmur, "~> 0.1"},
    {:jido_murmur_web, "~> 0.1"}
  ]
end
```

Add the CSS source directive to your `app.css` so Tailwind picks up component classes:

```css
@source "../../../deps/jido_murmur_web";
```

## Usage

### Option A: Direct Import

Import all components at once:

```elixir
defmodule MyAppWeb.ChatLive do
  use MyAppWeb, :live_view
  use JidoMurmurWeb.Components

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex h-full">
        <.workspace_list workspaces={@workspaces} current_id={@workspace.id} />
        <div class="flex-1 flex flex-col">
          <.agent_header agent={@agent} />
          <div id="messages" phx-update="stream">
            <div :for={{id, msg} <- @streams.messages} id={id}>
              <.chat_message message={msg} />
            </div>
          </div>
          <.streaming_indicator streaming?={@streaming?} />
          <.message_input form={@form} />
        </div>
        <.artifact_panel artifacts={@artifacts} />
      </div>
    </Layouts.app>
    """
  end
end
```

Or import individual components:

```elixir
import JidoMurmurWeb.Components.ChatMessage
import JidoMurmurWeb.Components.StreamingIndicator
```

### Option B: Generator (Copy to Your Project)

Copy component source files into your project for full customization:

```bash
# Copy all components
mix jido_murmur_web.install all

# Copy specific groups
mix jido_murmur_web.install chat        # ChatMessage, MessageInput, StreamingIndicator
mix jido_murmur_web.install workspace   # WorkspaceList
mix jido_murmur_web.install artifacts   # ArtifactPanel
```

Copied files land in `lib/my_app_web/components/jido_murmur/` with your app's namespace.

## Components

| Component | Function | Description |
|-----------|----------|-------------|
| `ChatMessage` | `chat_message/1` | Canonical chat bubble for in-progress or completed messages, including thinking, tool calls, and usage |
| `AgentHeader` | `agent_header/1` | Agent column header with name, color, status |
| `MessageInput` | `message_input/1` | Chat textarea with Enter-to-send keyboard shortcut |
| `StreamingIndicator` | `streaming_indicator/1` | Agent busy/idle animation |
| `AgentSelector` | `agent_selector/1` | Add-agent dialog with profile list |
| `WorkspaceList` | `workspace_list/1` | Sidebar workspace navigation |
| `ArtifactPanel` | `artifact_panel/1` | Side panel with artifact tabs and configurable renderers |

## Artifact Renderers

`ArtifactPanel` dispatches rendering to a configurable renderer registry. Register custom renderers:

```elixir
config :jido_murmur_web,
  artifact_renderers: %{
    "application/pdf" => MyAppWeb.PdfRenderer,
    "text/markdown" => MyAppWeb.MarkdownRenderer
  }
```

## License

See LICENSE file.
