defmodule MurmurWeb.Markdown do
  @moduledoc "Renders Markdown content as safe HTML using MDEx."

  @mdex_options [
    extension: [
      autolink: true,
      strikethrough: true,
      table: true,
      tasklist: true
    ],
    parse: [
      relaxed_autolinks: true,
      relaxed_tasklist_matching: true
    ],
    render: [
      full_info_string: true,
      github_pre_lang: true
    ],
    syntax_highlight: [
      formatter: {:html_inline, theme: "github_light"}
    ]
  ]

  @doc "Converts markdown text to a Phoenix-safe HTML string."
  def render(nil), do: ""
  def render(""), do: ""

  def render(text) when is_binary(text) do
    {:safe, MDEx.to_html!(text, @mdex_options)}
  end
end
