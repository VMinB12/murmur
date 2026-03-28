defmodule JidoMurmurWeb.Components.StreamingIndicator do
  @moduledoc """
  Renders a streaming status indicator for an agent.

  Shows a dot animation when the agent is actively streaming,
  and nothing when idle. Can also show token counts during streaming.

  ## Example

      <.streaming_indicator status={:busy} />
      <.streaming_indicator status={:idle} />
  """

  use Phoenix.Component

  @doc """
  Renders a streaming status indicator.

  ## Attributes

    * `status` — `:idle` or `:busy`.
    * `stream` — Optional streaming state map with `:content`, `:thinking`, `:tool_calls`.
      When provided and non-empty, shows additional context about what's streaming.
  """
  attr :status, :atom, default: :idle
  attr :stream, :map, default: nil

  def streaming_indicator(%{status: :busy} = assigns) do
    has_content? =
      assigns.stream && (assigns.stream.content != "" || assigns.stream.thinking != "" || assigns.stream.tool_calls != [])

    assigns = assign(assigns, :has_content?, has_content?)

    ~H"""
    <div class="flex items-center gap-1.5">
      <span class="loading loading-dots loading-xs text-warning"></span>
      <%= if @has_content? do %>
        <span class="text-[10px] text-base-content/40">Streaming...</span>
      <% else %>
        <span class="text-[10px] text-base-content/40">Thinking...</span>
      <% end %>
    </div>
    """
  end

  def streaming_indicator(assigns) do
    ~H""
  end
end
