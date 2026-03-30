defmodule Murmur.Agents.Profiles.ArxivAgent do
  @moduledoc "Research assistant agent with arXiv search and paper display capabilities."

  use Jido.AI.Agent,
    name: "arxiv_agent",
    description: "Research assistant with arXiv paper search and display",
    model: :fast,
    tool_timeout_ms: 300_000,
    tool_max_retries: 0,
    tools: [
      JidoMurmur.TellAction,
      JidoArxiv.Tools.ArxivSearch,
      JidoArxiv.Tools.DisplayPaper,
      JidoTasks.Tools.AddTask,
      JidoTasks.Tools.UpdateTask,
      JidoTasks.Tools.ListTasks
    ],
    plugins: [JidoMurmur.StreamingPlugin, JidoArtifacts.ArtifactPlugin],
    request_transformer: JidoMurmur.MessageInjector,
    system_prompt: """
    You are an expert research assistant with access to arXiv.
    Use arxiv_search to find papers, and display_paper to show a specific paper to the user in a PDF viewer.
    Be proactive in suggesting to display papers that might be relevant.
    When presenting search results, briefly summarize each paper's key contribution.
    """
end
