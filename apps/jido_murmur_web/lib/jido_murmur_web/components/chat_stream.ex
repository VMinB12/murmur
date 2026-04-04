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
      <div class="chat chat-start">
        <div class="chat-header mb-1 text-[10px] uppercase tracking-wider text-base-content/40 px-1">
          thinking
        </div>
        <details open class="collapse collapse-arrow w-full max-w-[85%] border border-base-300/50 bg-base-200/30 shadow-sm">
          <summary class="collapse-title flex min-h-0 items-center gap-1.5 py-2 pr-10 text-xs text-base-content/60">
            <.icon name="hero-light-bulb" class="w-3 h-3" />
            <span>Thinking...</span>
            <span class="loading loading-dots loading-xs text-base-content/40"></span>
          </summary>
          <div class="collapse-content px-4 pb-3 text-xs text-base-content/70 whitespace-pre-wrap break-words">
            {@stream.thinking}
          </div>
        </details>
      </div>
    <% end %>

    <%!-- Streaming tool calls --%>
    <%= for tc <- @stream.tool_calls do %>
      <div class="chat chat-start">
        <details open class="collapse collapse-arrow w-full max-w-[85%] border border-base-300/50 bg-base-200/20 shadow-sm">
          <summary class="collapse-title flex min-h-0 items-center gap-1.5 py-2 pr-10 text-xs text-base-content/70">
            <.icon name="hero-wrench-screwdriver" class="w-3 h-3 text-base-content/50" />
            <span class="font-medium">{tc.name}</span>
            <%= cond do %>
              <% tc.status == :running -> %>
                <span class="loading loading-dots loading-xs text-info/70"></span>
                <span class="text-info/70 text-[10px]">Running</span>
              <% tc.status == :completed -> %>
                <span class="text-success/70 text-[10px]">Completed</span>
              <% true -> %>
                <span class="text-error/70 text-[10px]">Error</span>
            <% end %>
          </summary>
          <%= if tool_call_args?(tc) && tc.status == :running do %>
            <div class="collapse-content px-0 pb-0 text-xs overflow-hidden">
              <div class="bg-base-200/20 px-3 py-1.5">
                <span class="text-[10px] uppercase tracking-wider text-base-content/40">
                  Arguments
                </span>
                <div class="mt-0.5 text-base-content/70 whitespace-pre-wrap break-words font-mono text-[11px]">
                  {Jason.encode!(tool_call_args(tc), pretty: true)}
                </div>
              </div>
            </div>
          <% end %>
          <%= if tool_call_result?(tc) do %>
            <div class="collapse-content px-0 pb-0 text-xs overflow-hidden">
              <div class="bg-base-200/20 px-3 py-1.5">
                <span class="text-[10px] uppercase tracking-wider text-base-content/40">
                  Result
                </span>
                <div class="mt-0.5 text-base-content/70 whitespace-pre-wrap break-words">
                  {tool_call_result(tc)}
                </div>
              </div>
            </div>
          <% end %>
        </details>
      </div>
    <% end %>

    <%!-- Streaming tokens --%>
    <%= if @stream.content != "" do %>
      <div class="chat chat-start">
        <div class="chat-header mb-1 text-[10px] uppercase tracking-wider text-base-content/40 px-1">
          assistant
        </div>
        <div class={[
          "chat-bubble px-3 py-2 text-sm max-w-[85%] whitespace-pre-wrap break-words shadow-sm",
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

  defp tool_call_args(tool_call), do: Map.get(tool_call, :args) || %{}

  defp tool_call_args?(tool_call) do
    args = tool_call_args(tool_call)

    cond do
      is_map(args) -> map_size(args) > 0
      is_list(args) -> args != []
      true -> args not in [nil, ""]
    end
  end

  defp tool_call_result(tool_call), do: Map.get(tool_call, :result)
  defp tool_call_result?(tool_call), do: tool_call_result(tool_call) not in [nil, ""]
end
