defmodule MurmurWeb.Components.Artifacts.PaperList do
  @moduledoc "Artifact renderer for lists of arxiv papers."

  use Phoenix.Component

  import MurmurWeb.CoreComponents, only: [icon: 1]

  @doc "Compact badge for the chat column."
  attr :data, :any, required: true
  attr :session_id, :string, required: true
  attr :active?, :boolean, default: false

  def badge(assigns) do
    ~H"""
    <button
      phx-click="open_artifact"
      phx-value-session-id={@session_id}
      phx-value-name="papers"
      class={[
        "inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-medium transition-colors cursor-pointer",
        if(@active?,
          do: "bg-primary/20 text-primary ring-1 ring-primary/30",
          else: "bg-base-200/60 text-base-content/60 hover:bg-base-200 hover:text-base-content/80"
        )
      ]}
    >
      <.icon name="hero-academic-cap" class="w-3 h-3" />
      <span>{length(@data)} papers</span>
    </button>
    """
  end

  @doc "Full detail renderer for the artifact panel."
  attr :data, :any, required: true
  attr :session_id, :string, required: true

  def detail(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <div class="px-4 py-2 border-b border-base-300/50 flex items-center gap-2 shrink-0">
        <.icon name="hero-academic-cap" class="w-4 h-4 text-base-content/50" />
        <span class="text-sm font-medium">{length(@data)} papers found</span>
      </div>
      <div class="flex-1 overflow-y-auto">
        <div class="divide-y divide-base-300/30">
          <%= for paper <- @data do %>
            <% paper_id = paper["id"] || paper[:id] || "" %>
            <% paper_title = paper["title"] || paper[:title] || "Untitled" %>
            <% paper_abstract = paper["abstract"] || paper[:abstract] || "" %>
            <% paper_published = paper["published"] || paper[:published] || "" %>
            <% paper_url = paper["url"] || paper[:url] %>
            <% paper_pdf_url = paper["pdf_url"] || paper[:pdf_url] %>
            <div class="px-4 py-3 hover:bg-base-200/30 transition-colors group/paper">
              <div class="flex items-start justify-between gap-3">
                <div class="min-w-0 flex-1">
                  <div class="text-sm font-medium text-base-content leading-snug">
                    {paper_title}
                  </div>
                  <div class="flex items-center gap-2 mt-1">
                    <span class="text-[11px] text-base-content/40 font-mono">{paper_id}</span>
                    <%= if paper_published != "" do %>
                      <span class="text-[11px] text-base-content/30">
                        {String.slice(paper_published, 0, 10)}
                      </span>
                    <% end %>
                  </div>
                  <%= if paper_abstract != "" do %>
                    <p class="text-xs text-base-content/50 mt-1.5 leading-relaxed line-clamp-3">
                      {paper_abstract}
                    </p>
                  <% end %>
                </div>
                <div class="flex items-center gap-1 shrink-0 pt-0.5">
                  <%= if paper_url do %>
                    <a
                      href={paper_url}
                      target="_blank"
                      rel="noopener"
                      class="btn btn-ghost btn-xs opacity-40 group-hover/paper:opacity-80 hover:!opacity-100"
                      title="View on arxiv"
                    >
                      <.icon name="hero-arrow-top-right-on-square" class="w-3.5 h-3.5" />
                    </a>
                  <% end %>
                  <%= if paper_pdf_url do %>
                    <a
                      href={paper_pdf_url}
                      target="_blank"
                      rel="noopener"
                      class="btn btn-ghost btn-xs opacity-40 group-hover/paper:opacity-80 hover:!opacity-100"
                      title="Open PDF"
                    >
                      <.icon name="hero-document-arrow-down" class="w-3.5 h-3.5" />
                    </a>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
