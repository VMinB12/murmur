defmodule MurmurWeb.Components.Artifacts.Generic do
  @moduledoc "Fallback artifact renderer for unknown types."

  use Phoenix.Component

  import MurmurWeb.CoreComponents, only: [icon: 1]

  @doc "Compact badge for the chat column."
  attr :name, :string, required: true
  attr :data, :any, required: true
  attr :session_id, :string, required: true
  attr :active?, :boolean, default: false

  def badge(assigns) do
    count =
      if is_list(assigns.data) do
        " (#{length(assigns.data)})"
      else
        ""
      end

    assigns = assign(assigns, :count, count)

    ~H"""
    <button
      phx-click="open_artifact"
      phx-value-session-id={@session_id}
      phx-value-name={@name}
      class={[
        "inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-medium transition-colors cursor-pointer",
        if(@active?,
          do: "bg-primary/20 text-primary ring-1 ring-primary/30",
          else: "bg-base-200/60 text-base-content/60 hover:bg-base-200 hover:text-base-content/80"
        )
      ]}
    >
      <.icon name="hero-square-3-stack-3d" class="w-3 h-3" />
      <span>{@name}{@count}</span>
    </button>
    """
  end

  @doc "Full detail renderer for the artifact panel."
  attr :name, :string, required: true
  attr :data, :any, required: true
  attr :session_id, :string, required: true

  def detail(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <div class="px-4 py-2 border-b border-base-300/50 flex items-center gap-2 shrink-0">
        <.icon name="hero-square-3-stack-3d" class="w-4 h-4 text-base-content/50" />
        <span class="text-sm font-medium">{@name}</span>
        <%= if is_list(@data) do %>
          <span class="text-[11px] text-base-content/40">({length(@data)} items)</span>
        <% end %>
      </div>
      <div class="flex-1 overflow-y-auto px-4 py-3 text-xs text-base-content/70">
        <%= cond do %>
          <% is_list(@data) -> %>
            <div class="space-y-1">
              <%= for {item, idx} <- Enum.with_index(@data) do %>
                <div class="flex gap-2 py-0.5 border-b border-base-300/30 last:border-b-0">
                  <span class="text-base-content/30 shrink-0">{idx + 1}.</span>
                  <span class="break-words min-w-0">{format_item(item)}</span>
                </div>
              <% end %>
            </div>
          <% is_map(@data) -> %>
            <pre class="whitespace-pre-wrap break-words text-[11px]" phx-no-curly-interpolation>{Jason.encode!(@data, pretty: true)}</pre>
          <% true -> %>
            <span class="whitespace-pre-wrap break-words">{inspect(@data)}</span>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_item(item) when is_map(item) do
    item[:title] || item["title"] ||
      item[:name] || item["name"] ||
      item[:label] || item["label"] ||
      inspect(item, limit: 80)
  end

  defp format_item(item) when is_binary(item), do: item
  defp format_item(item), do: inspect(item, limit: 80)
end
