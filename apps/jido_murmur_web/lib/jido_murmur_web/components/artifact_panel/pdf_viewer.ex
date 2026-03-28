defmodule JidoMurmurWeb.Components.ArtifactPanel.PdfViewer do
  @moduledoc "Artifact renderer for displaying a single PDF in an iframe."

  use Phoenix.Component

  import JidoMurmurWeb, only: [icon: 1]

  @doc "Compact badge for the chat column."
  attr :name, :string, default: "displayed_paper"
  attr :data, :any, required: true
  attr :session_id, :string, required: true
  attr :active?, :boolean, default: false

  def badge(assigns) do
    title =
      assigns.data["title"] || assigns.data[:title] ||
        assigns.data["id"] || assigns.data[:id] || "PDF"

    assigns = assign(assigns, :display_title, title)

    ~H"""
    <button
      phx-click="open_artifact"
      phx-value-session-id={@session_id}
      phx-value-name="displayed_paper"
      class={[
        "inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-medium transition-colors cursor-pointer max-w-[200px]",
        if(@active?,
          do: "bg-primary/20 text-primary ring-1 ring-primary/30",
          else: "bg-base-200/60 text-base-content/60 hover:bg-base-200 hover:text-base-content/80"
        )
      ]}
    >
      <.icon name="hero-document" class="w-3 h-3 shrink-0" />
      <span class="truncate">{@display_title}</span>
    </button>
    """
  end

  @doc "Full detail renderer for the artifact panel."
  attr :name, :string, default: "displayed_paper"
  attr :data, :any, required: true
  attr :session_id, :string, required: true

  def detail(assigns) do
    paper_id = assigns.data["id"] || assigns.data[:id] || ""
    pdf_url = assigns.data["pdf_url"] || assigns.data[:pdf_url] || ""
    paper_title = assigns.data["title"] || assigns.data[:title] || paper_id

    assigns =
      assigns
      |> assign(:paper_id, paper_id)
      |> assign(:pdf_url, pdf_url)
      |> assign(:paper_title, paper_title)

    ~H"""
    <div class="h-full flex flex-col">
      <div class="px-4 py-2 border-b border-base-300/50 flex items-center justify-between shrink-0">
        <div class="flex items-center gap-2 min-w-0">
          <.icon name="hero-document" class="w-4 h-4 text-base-content/50 shrink-0" />
          <span class="text-sm font-medium truncate">{@paper_title}</span>
          <span class="text-[11px] text-base-content/40 font-mono shrink-0">{@paper_id}</span>
        </div>
        <a
          href={@pdf_url}
          target="_blank"
          rel="noopener noreferrer"
          class="btn btn-ghost btn-xs text-base-content/50 hover:text-base-content shrink-0"
        >
          Open in new tab <.icon name="hero-arrow-top-right-on-square" class="w-3 h-3 ml-1" />
        </a>
      </div>
      <div class="flex-1 min-h-0">
        <iframe src={@pdf_url} class="w-full h-full border-0" title={"PDF: #{@paper_id}"}></iframe>
      </div>
    </div>
    """
  end
end
