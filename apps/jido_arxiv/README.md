# JidoArxiv

Academic research tools for [Jido](https://github.com/agentjido/jido) agents. Search [arXiv](https://arxiv.org) and display paper details — enabling agents to help with literature review and research discovery.

## Installation

```elixir
def deps do
  [
    {:jido_murmur, "~> 0.1"},
    {:jido_arxiv, "~> 0.1"}
  ]
end
```

No migrations required — this package is stateless.

## Usage

Add arXiv tools to an agent profile:

```elixir
defmodule MyApp.Agents.ResearchAgent do
  use Jido.AI.Agent,
    name: "researcher",
    description: "Academic research assistant",
    model: :capable,
    tools: [
      JidoMurmur.TellAction,
      JidoArxiv.Tools.ArxivSearch,
      JidoArxiv.Tools.DisplayPaper
    ],
    plugins: [JidoMurmur.StreamingPlugin, JidoMurmur.ArtifactPlugin],
    system_prompt: "You are a research assistant. Search arXiv for papers."

  def catalog_meta, do: %{color: "amber"}
end
```

## Tools

| Module | Description |
|--------|-------------|
| `JidoArxiv.Tools.ArxivSearch` | Searches the arXiv API by query, returning matching papers with titles, authors, and abstracts |
| `JidoArxiv.Tools.DisplayPaper` | Emits an artifact signal containing paper details for UI rendering |

## License

See LICENSE file.
