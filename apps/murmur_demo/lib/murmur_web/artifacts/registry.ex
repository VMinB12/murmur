defmodule MurmurWeb.Artifacts.Registry do
  @moduledoc """
  Demo-owned artifact renderer registry.

  The generic `jido_murmur_web` package owns the artifact chrome and fallback
  behavior. The demo app owns the mapping from artifact names to domain-specific
  renderers.
  """

  alias MurmurWeb.Components.Artifacts.PaperList
  alias MurmurWeb.Components.Artifacts.PdfViewer
  alias MurmurWeb.Components.Artifacts.SqlResults

  @renderers %{
    "papers" => PaperList,
    "displayed_paper" => PdfViewer,
    "sql_results" => SqlResults
  }

  @spec renderers() :: %{optional(String.t()) => module()}
  def renderers, do: @renderers

  @spec merge(map()) :: map()
  def merge(renderers) when is_map(renderers), do: Map.merge(@renderers, renderers)
end
