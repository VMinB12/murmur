defmodule <%= @app_module %>Web.Components.ChatMessage do
  @moduledoc """
  Renders a single chat message bubble with optional thinking trace,
  tool call details, and usage statistics.
  """

  use Phoenix.Component

  alias JidoMurmur.DisplayMessage
  alias JidoMurmur.HiddenContent

  import <%= @app_module %>Web.CoreComponents, only: [icon: 1]

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

      <%%= if Map.get(@message, :thinking) do %>
        <details class="w-full max-w-[85%%] group">
          <summary class="flex items-center gap-1.5 cursor-pointer text-xs text-base-content/50 hover:text-base-content/70 px-1 py-0.5 transition-colors">
            <.icon name="hero-light-bulb" class="w-3 h-3" />
            <span>Thinking...</span>
            <.icon name="hero-chevron-right" class="w-3 h-3 transition-transform group-open:rotate-90" />
          </summary>
          <div class="mt-1 rounded-lg bg-base-200/50 border border-base-300/50 px-3 py-2 text-xs text-base-content/60 whitespace-pre-wrap break-words">
            {@message.thinking}
          </div>
        </details>
      <%% end %>

      <%%= for tc <- Map.get(@message, :tool_calls, []) do %>
        <details class="w-full max-w-[85%%] group">
          <summary class="flex items-center gap-1.5 cursor-pointer text-xs px-1 py-0.5 transition-colors hover:text-base-content/70">
            <.icon name="hero-wrench-screwdriver" class="w-3 h-3 text-base-content/50" />
            <span class="font-medium">{tc.name}</span>
            <.icon name="hero-chevron-right" class="w-3 h-3 text-base-content/40 transition-transform group-open:rotate-90" />
          </summary>
        </details>
      <%% end %>

      <%%= if @message.content && @message.content != "" do %>
        <%% inter_agent? = DisplayMessage.external_user_message?(@message) %>
        <%% render_markdown? = render_markdown_message?(@message) %>
        <div class={[
          "rounded-xl px-3 py-2 text-sm max-w-[85%%] break-words",
          cond do
            DisplayMessage.assistant_message?(@message) ->
              ["bg-base-200 text-base-content rounded-bl-sm", markdown_bubble_classes()]

            render_markdown? && @color ->
              [@color.dot, "text-white rounded-br-sm", markdown_bubble_classes()]

            inter_agent? && @color ->
              [@color.dot, "text-white rounded-br-sm whitespace-pre-wrap"]

            true ->
              "bg-primary text-primary-content rounded-br-sm whitespace-pre-wrap"
          end
        ]}>
          <%%= if render_markdown? do %>
            {render_content(@message.content, @markdown_renderer)}
          <%% else %>
            {@message.content}
          <%% end %>
        </div>
      <%% end %>
    </div>
    """
  end

  defp render_content(content, nil), do: content
  defp render_content(content, renderer) when is_function(renderer, 1), do: renderer.(content)

  defp render_markdown_message?(message) when is_map(message) do
    DisplayMessage.assistant_message?(message) or
      (DisplayMessage.external_user_message?(message) and
         HiddenContent.wrapped?(Map.get(message, :content, "")))
  end

  defp markdown_bubble_classes do
    "prose prose-sm max-w-none [&_*]:text-inherit [&_p]:my-0 [&_pre]:whitespace-pre-wrap"
  end
end
