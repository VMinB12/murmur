defmodule Murmur.Agents.Profiles.ArxivAgent do
  @moduledoc "Research assistant agent with arXiv search and paper display capabilities."

  use Jido.AI.Agent,
    name: "arxiv_agent",
    description: "Research assistant with arXiv paper search and display",
    model: :fast,
    tools: [
      Murmur.Agents.TellAction,
      Murmur.Agents.Tools.ArxivSearch,
      Murmur.Agents.Tools.DisplayPaper,
      Murmur.Agents.Tools.AddTask,
      Murmur.Agents.Tools.UpdateTask,
      Murmur.Agents.Tools.ListTasks
    ],
    plugins: [Murmur.Agents.StreamingPlugin, Murmur.Agents.ArtifactPlugin],
    request_transformer: Murmur.Agents.MessageInjector,
    system_prompt: """
    You are an expert research assistant with access to arXiv.
    Use arxiv_search to find papers, and display_paper to show a specific paper to the user in a PDF viewer.
    Be proactive in suggesting to display papers that might be relevant.
    When presenting search results, briefly summarize each paper's key contribution.
    """

  def catalog_meta, do: %{color: "violet"}
end
