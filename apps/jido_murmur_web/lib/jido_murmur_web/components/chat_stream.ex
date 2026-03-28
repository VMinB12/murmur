defmodule JidoMurmurWeb.Components.ChatStream do
  @moduledoc """
  Renders the live-streaming state for an agent: thinking trace,
  in-progress tool calls, and token-by-token content output with
  an animated cursor.

  ## Example

      <.chat_stream stream={@streaming[session.id]} />
  """

  use Phoenix.Component

  import JidoMurmurWeb, only: [icon: 1]

  @doc """
  Renders streaming state (thinking, tool calls, content tokens).

  ## Attributes

    * `stream` — Map with `:content`, `:thinking`, `:tool_calls` keys.
    * `color` — Optional color map with `:bg` key for background styling.
  """
  attr :stream, :map, required: true
  attr :color, :map, default: nil

  def chat_stream(assigns) do
    ~H"""
    <%!-- Streaming thinking --%>
    <%= if @stream.thinking != "" do %>
      <div class="flex flex-col gap-0.5 items-start">
        <details open class="w-full max-w-[85%] group">
          <summary class="flex items-center gap-1.5 cursor-pointer text-xs text-base-content/50 hover:text-base-content/70 px-1 py-0.5 transition-colors">
            <.icon name="hero-light-bulb" class="w-3 h-3" />
            <span>Thinking...</span>
            <span class="loading loading-dots loading-xs text-base-content/40"></span>
            <.icon
              name="hero-chevron-right"
              class="w-3 h-3 transition-transform group-open:rotate-90"
            />
          </summary>
          <div class="mt-1 rounded-lg bg-base-200/50 border border-base-300/50 px-3 py-2 text-xs text-base-content/60 whitespace-pre-wrap break-words">
            {@stream.thinking}
          </div>
        </details>
      </div>
    <% end %>

    <%!-- Streaming tool calls --%>
    <%= for tc <- @stream.tool_calls do %>
      <div class="flex flex-col gap-0.5 items-start">
        <details open class="w-full max-w-[85%] group">
          <summary class="flex items-center gap-1.5 cursor-pointer text-xs px-1 py-0.5 transition-colors hover:text-base-content/70">
            <.icon name="hero-wrench-screwdriver" class="w-3 h-3 text-base-content/50" />
            <span class="font-medium">{tc.name}</span>
            <%= if tc.status == :completed do %>
              <span class="text-success/70 text-[10px]">Completed</span>
            <% else %>
              <span class="text-error/70 text-[10px]">Error</span>
            <% end %>
            <.icon
              name="hero-chevron-right"
              class="w-3 h-3 text-base-content/40 transition-transform group-open:rotate-90"
            />
          </summary>
          <%= if tc[:result] do %>
            <div class="mt-1 rounded-lg border border-base-300/50 text-xs overflow-hidden">
              <div class="bg-base-200/20 px-3 py-1.5">
                <span class="text-[10px] uppercase tracking-wider text-base-content/40">
                  Result
                </span>
                <div class="mt-0.5 text-base-content/70 whitespace-pre-wrap break-words">
                  {tc.result}
                </div>
              </div>
            </div>
          <% end %>
        </details>
      </div>
    <% end %>

    <%!-- Streaming tokens --%>
    <%= if @stream.content != "" do %>
      <div class="flex flex-col gap-0.5 items-start">
        <span class="text-[10px] uppercase tracking-wider text-base-content/40 px-1">
          assistant
        </span>
        <div class={[
          "rounded-xl rounded-bl-sm px-3 py-2 text-sm max-w-[85%] whitespace-pre-wrap break-words",
          if(@color, do: ["border border-base-300/30", @color.bg], else: "bg-base-200 text-base-content")
        ]}>
          {@stream.content}
          <span class="inline-block w-1 h-4 bg-primary animate-pulse ml-0.5 align-text-bottom">
          </span>
        </div>
      </div>
    <% end %>
    """
  end
end
