defmodule MurmurWeb.Markdown do
  @moduledoc "Renders Markdown content as safe HTML using MDEx."

  @doc "Converts markdown text to a Phoenix-safe HTML string."
  def render(nil), do: ""
  def render(""), do: ""

  # sobelow_skip ["XSS.Raw"]
  def render(text) when is_binary(text) do
    text
    |> MDEx.to_html!()
    |> Phoenix.HTML.raw()
  end
end
