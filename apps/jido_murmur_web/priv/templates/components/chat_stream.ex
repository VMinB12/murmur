defmodule <%= @app_module %>Web.Components.ChatStream do
  @moduledoc """
  Renders the live-streaming state for an agent: thinking trace,
  in-progress tool calls, and token-by-token content output.
  """

  use Phoenix.Component

  import <%= @app_module %>Web.CoreComponents, only: [icon: 1]

  attr :stream, :map, required: true
  attr :color, :map, default: nil

  def chat_stream(assigns) do
    ~H"""
    <%%= if @stream.thinking != "" do %>
      <div class="flex flex-col gap-0.5 items-start">
        <details open class="w-full max-w-[85%%] group">
          <summary class="flex items-center gap-1.5 cursor-pointer text-xs text-base-content/50 hover:text-base-content/70 px-1 py-0.5 transition-colors">
            <.icon name="hero-light-bulb" class="w-3 h-3" />
            <span>Thinking...</span>
            <span class="loading loading-dots loading-xs text-base-content/40"></span>
          </summary>
          <div class="mt-1 rounded-lg bg-base-200/50 border border-base-300/50 px-3 py-2 text-xs text-base-content/60 whitespace-pre-wrap break-words">
            {@stream.thinking}
          </div>
        </details>
      </div>
    <%% end %>

    <%%= if @stream.content != "" do %>
      <div class="flex flex-col gap-0.5 items-start">
        <span class="text-[10px] uppercase tracking-wider text-base-content/40 px-1">assistant</span>
        <div class={[
          "rounded-xl rounded-bl-sm px-3 py-2 text-sm max-w-[85%%] whitespace-pre-wrap break-words",
          if(@color, do: ["border border-base-300/30", @color.bg], else: "bg-base-200 text-base-content")
        ]}>
          {@stream.content}
          <span class="inline-block w-1 h-4 bg-primary animate-pulse ml-0.5 align-text-bottom"></span>
        </div>
      </div>
    <%% end %>
    """
  end
end
