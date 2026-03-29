defmodule JidoArxiv.Tools.DisplayPaper do
  @moduledoc """
  Displays a single arXiv paper to the user in a PDF viewer.

  Emits a `"displayed_paper"` artifact (mode: `:replace`) so the LiveView
  renders an iframe with the PDF. The LLM receives a short confirmation.
  """

  use Jido.Action,
    name: "display_paper",
    description:
      "Display an arXiv paper to the user. " <>
        "Opens a PDF viewer in the UI. Use after searching to show a specific paper the user is interested in.",
    schema: [
      arxiv_id: [type: :string, required: true, doc: "The arXiv paper ID (e.g. 2301.07041)"]
    ]

  alias JidoArtifacts.Artifact

  @impl true
  def run(params, ctx) do
    arxiv_id = normalize_arxiv_id(params.arxiv_id)

    if arxiv_id == "" do
      {:error, "Invalid arXiv ID: #{params.arxiv_id}"}
    else
      paper = %{
        id: arxiv_id,
        url: "https://arxiv.org/abs/#{arxiv_id}",
        pdf_url: "https://arxiv.org/pdf/#{arxiv_id}.pdf"
      }

      artifact_directive = Artifact.emit(ctx, "displayed_paper", paper)

      {:ok, %{result: "Displaying PDF for arXiv paper #{arxiv_id}"}, artifact_directive}
    end
  end

  defp normalize_arxiv_id(id) do
    id
    |> String.trim()
    |> strip_url()
    |> String.trim_trailing(".pdf")
  end

  defp strip_url(id) do
    if String.starts_with?(id, "http://") or String.starts_with?(id, "https://") do
      id |> String.trim_trailing("/") |> String.split("/") |> List.last("")
    else
      id
    end
  end
end
