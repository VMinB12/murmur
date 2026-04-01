# jido_arxiv — arXiv Research Tools

## Purpose

Stateless Elixir package providing academic research tools for Jido agents. Enables agents to search the arXiv API and display academic papers. Designed as Jido.Action-based tools with artifact integration — no database or stateful dependencies.

## Public API

### ArxivSearch (Jido.Action)

- **Action name:** `arxiv_search`
- **Input:** `query: string` (required)
- **Output:** LLM summary (numbered list, max 5 papers) + `"papers"` artifact with `:append` merge
- **HTTP:** `GET https://export.arxiv.org/api/query` with 10s pool / 20s receive timeout

### DisplayPaper (Jido.Action)

- **Action name:** `display_paper`
- **Input:** `arxiv_id: string` (required — accepts ID, abs URL, or PDF URL)
- **Output:** Confirmation message + `"displayed_paper"` artifact with `:replace` merge
- **URL normalization:** Strips http(s), removes `.pdf` extension, extracts ID

## Internal Architecture

### Search Flow

```
User query → URI-encode → arXiv Atom API → Parse XML (SweetXml)
    → Transform to paper maps → Format for LLM → Emit artifact
```

### Paper Map Structure

```elixir
%{
  id: "2301.07041v1",
  title: "Paper Title",
  abstract: "First 200+ chars...",
  published: "2023-01-17T...",
  url: "https://arxiv.org/abs/2301.07041v1",
  pdf_url: "https://arxiv.org/pdf/2301.07041v1.pdf"
}
```

### Error Handling

- HTTP 429 → rate limit message
- HTTP 5xx/4xx → generic error
- Connection errors → wrapped exception
- Malformed XML → empty results (graceful degradation)

## Dependencies

**Requires:** `jido ~> 2.0`, `jido_action ~> 2.0`, `jido_artifacts` (umbrella), `req ~> 0.5`, `sweet_xml ~> 0.7`, `jason ~> 1.2`

**Used by:** `murmur_demo` (ArxivAgent profile)

## Configuration

No required config. Optional:

```elixir
# Override req options (for testing)
config :jido_arxiv, :req_options, [plug: {Req.Test, ArxivSearch}]
```
