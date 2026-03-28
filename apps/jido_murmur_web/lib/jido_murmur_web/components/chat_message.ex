defmodule JidoMurmurWeb.Components.ChatMessage do
  @moduledoc """
  Renders a single chat message bubble with optional thinking trace,
  tool call details, and usage statistics.

  ## Example

      <.chat_message message={msg} color={color} />
  """

  use Phoenix.Component

  import JidoMurmurWeb, only: [icon: 1]

  @doc """
  Renders a chat message with role-aware styling.

  ## Attributes

    * `message` — Map with `:id`, `:role`, `:content`, `:sender_name`,
      and optional `:thinking`, `:tool_calls`, `:usage`.
    * `color` — Optional color map with `:dot`, `:text`, `:bg` keys for
      inter-agent message styling. Falls back to primary bubble for user messages.
    * `markdown_renderer` — Optional function `(String.t() -> Phoenix.HTML.safe())`
      to render markdown in assistant messages. Defaults to raw text output.
  """
  attr :message, :map, required: true
  attr :color, :map, default: nil
  attr :markdown_renderer, :any, default: nil

  def chat_message(assigns) do
    ~H"""
    <div
      id={"msg-#{@message.id}"}
      class={[
        "flex flex-col gap-0.5",
        if(@message.role == "user", do: "items-end", else: "items-start")
      ]}
    >
      <span class="text-[10px] uppercase tracking-wider text-base-content/40 px-1">
        {@message.sender_name || @message.role}
      </span>

      <%!-- Thinking trace (collapsible) --%>
      <%= if Map.get(@message, :thinking) do %>
        <details class="w-full max-w-[85%] group">
          <summary class="flex items-center gap-1.5 cursor-pointer text-xs text-base-content/50 hover:text-base-content/70 px-1 py-0.5 transition-colors">
            <.icon name="hero-light-bulb" class="w-3 h-3" />
            <span>Thinking...</span>
            <.icon
              name="hero-chevron-right"
              class="w-3 h-3 transition-transform group-open:rotate-90"
            />
          </summary>
          <div class="mt-1 rounded-lg bg-base-200/50 border border-base-300/50 px-3 py-2 text-xs text-base-content/60 whitespace-pre-wrap break-words">
            {@message.thinking}
          </div>
        </details>
      <% end %>

      <%!-- Tool calls (collapsible) --%>
      <%= for tc <- Map.get(@message, :tool_calls, []) do %>
        <details class="w-full max-w-[85%] group">
          <summary class="flex items-center gap-1.5 cursor-pointer text-xs px-1 py-0.5 transition-colors hover:text-base-content/70">
            <.icon name="hero-wrench-screwdriver" class="w-3 h-3 text-base-content/50" />
            <span class="font-medium">{tc.name}</span>
            <.tool_status status={tc.status} />
            <.icon
              name="hero-chevron-right"
              class="w-3 h-3 text-base-content/40 transition-transform group-open:rotate-90"
            />
          </summary>
          <div class="mt-1 rounded-lg border border-base-300/50 text-xs overflow-hidden">
            <%= if tc[:args] && tc.args != %{} do %>
              <div class="bg-base-200/30 px-3 py-1.5 border-b border-base-300/50">
                <span class="text-[10px] uppercase tracking-wider text-base-content/40">
                  Arguments
                </span>
                <pre class="mt-0.5 text-base-content/70 whitespace-pre-wrap break-words">{Jason.encode!(tc.args, pretty: true)}</pre>
              </div>
            <% end %>
            <%= if tc[:result] do %>
              <div class="bg-base-200/20 px-3 py-1.5">
                <span class="text-[10px] uppercase tracking-wider text-base-content/40">
                  Result
                </span>
                <div class="mt-0.5 text-base-content/70 whitespace-pre-wrap break-words">
                  {tc.result}
                </div>
              </div>
            <% end %>
          </div>
        </details>
      <% end %>

      <%!-- Message content --%>
      <%= if @message.content && @message.content != "" do %>
        <% inter_agent? =
          @message.role == "user" and @message.sender_name != "You" and
            @message.sender_name != nil %>
        <div class={[
          "rounded-xl px-3 py-2 text-sm max-w-[85%] break-words",
          cond do
            @message.role != "user" ->
              "bg-base-200 text-base-content rounded-bl-sm prose prose-sm max-w-none"

            inter_agent? && @color ->
              [@color.dot, "text-white rounded-br-sm whitespace-pre-wrap"]

            true ->
              "bg-primary text-primary-content rounded-br-sm whitespace-pre-wrap"
          end
        ]}>
          <%= if @message.role == "user" do %>
            {@message.content}
          <% else %>
            {render_content(@message.content, @markdown_renderer)}
          <% end %>
        </div>
        <.usage_tooltip usage={Map.get(@message, :usage)} />
      <% end %>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp tool_status(%{status: :completed} = assigns) do
    ~H"""
    <span class="text-success/70 text-[10px]">Completed</span>
    """
  end

  defp tool_status(%{status: :error} = assigns) do
    ~H"""
    <span class="text-error/70 text-[10px]">Error</span>
    """
  end

  defp tool_status(assigns) do
    ~H"""
    <span class="loading loading-spinner loading-xs text-warning"></span>
    """
  end

  attr :usage, :map, default: nil

  defp usage_tooltip(%{usage: nil} = assigns), do: ~H""

  defp usage_tooltip(assigns) do
    ~H"""
    <div class="group/usage relative inline-flex items-center px-1">
      <.icon
        name="hero-information-circle"
        class="w-3 h-3 text-base-content/30 hover:text-base-content/60 cursor-help transition-colors"
      />
      <div class="absolute bottom-full left-0 mb-1 hidden group-hover/usage:block z-10">
        <div class="bg-base-300 text-base-content text-[10px] rounded-lg px-2.5 py-1.5 shadow-lg border border-base-content/10 whitespace-nowrap">
          <div class="flex items-center gap-3">
            <span>{Map.get(@usage, :input_tokens, 0)} in</span>
            <span>{Map.get(@usage, :output_tokens, 0)} out</span>
            <span class="font-medium">{Map.get(@usage, :total_tokens, 0)} total</span>
            <%= if Map.get(@usage, :duration_ms) do %>
              <span class="text-base-content/50">
                {Float.round(@usage.duration_ms / 1000, 1)}s
              </span>
            <% end %>
          </div>
          <%= if Map.get(@usage, :model) do %>
            <div class="text-base-content/50 mt-0.5">{@usage.model}</div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp render_content(content, nil), do: content
  defp render_content(content, renderer) when is_function(renderer, 1), do: renderer.(content)
end
