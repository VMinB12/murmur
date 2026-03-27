defmodule Murmur.Agents.Tools.ArxivSearch do
  @moduledoc """
  Searches the arXiv API and returns paper metadata.

  Emits a `"papers"` artifact (mode: `:append`) so the LiveView can
  display all papers found across multiple searches as a growing list.
  The LLM receives a concise text summary of the results.
  """

  use Jido.Action,
    name: "arxiv_search",
    description:
      "Search arXiv for academic papers. Returns titles, abstracts, and PDF links. " <>
        "Use this when the user asks about research topics, papers, or academic work.",
    schema: [
      query: [type: :string, required: true, doc: "The search query for arXiv"]
    ]

  import SweetXml, only: [sigil_x: 2, xpath: 3]

  alias Murmur.Agents.Artifact

  @arxiv_api_url "https://export.arxiv.org/api/query"
  @max_results 5

  @impl true
  def run(params, ctx) do
    case fetch_papers(params.query) do
      {:ok, papers} ->
        llm_summary = format_for_llm(papers)
        artifact_directive = Artifact.emit(ctx, "papers", papers, mode: :append)

        {:ok, %{result: llm_summary}, artifact_directive}

      {:error, reason} ->
        {:error, "arXiv search failed: #{reason}"}
    end
  end

  defp fetch_papers(query) do
    url =
      @arxiv_api_url <>
        "?" <>
        URI.encode_query(%{
          "search_query" => "all:#{query}",
          "start" => "0",
          "max_results" => to_string(@max_results),
          "sortBy" => "relevance",
          "sortOrder" => "descending"
        })

    case Req.get(url, receive_timeout: 20_000, redirect: true) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, parse_atom_feed(body)}

      {:ok, %Req.Response{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp parse_atom_feed(xml) when is_binary(xml) do
    xml
    |> xpath(
      ~x"//entry"l,
      id: ~x"./id/text()"s,
      title: ~x"./title/text()"s,
      abstract: ~x"./summary/text()"s,
      published: ~x"./published/text()"s
    )
    |> Enum.map(fn entry ->
      arxiv_id = extract_arxiv_id(entry.id)

      %{
        id: arxiv_id,
        title: normalize_whitespace(entry.title),
        abstract: normalize_whitespace(entry.abstract),
        published: entry.published,
        url: abs_url(arxiv_id),
        pdf_url: pdf_url(arxiv_id)
      }
    end)
  rescue
    _ -> []
  end

  defp extract_arxiv_id(raw_id) do
    raw_id
    |> String.trim()
    |> String.split("/")
    |> List.last("")
  end

  defp normalize_whitespace(text) do
    text |> String.trim() |> String.replace(~r/\s+/, " ")
  end

  defp abs_url(arxiv_id), do: "https://arxiv.org/abs/#{arxiv_id}"
  defp pdf_url(arxiv_id), do: "https://arxiv.org/pdf/#{arxiv_id}.pdf"

  defp format_for_llm(papers) do
    header = "Found #{length(papers)} papers:\n\n"

    body =
      papers
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {paper, idx} ->
        "#{idx}. **#{paper.title}** (#{paper.id})\n   #{String.slice(paper.abstract, 0, 200)}..."
      end)

    header <> body
  end
end
