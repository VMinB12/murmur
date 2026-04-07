defmodule MurmurWeb.MarkdownTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias JidoMurmur.DisplayMessage
  alias JidoMurmurWeb.Components.ChatMessage
  alias MurmurWeb.Markdown

  test "renders assistant markdown tables through the chat component" do
    message =
      DisplayMessage.assistant("""
      Here are the first three intents in a Markdown table:

      | Intent | Definition | Response expected | Example |
      | --- | --- | --- | --- |
      | notify | One-way information | No | FYI: completed |
      | request | Ask for a decision | Yes | Can you review? |
      | delegate | Assign a bounded subtask | Yes | Please prepare the dashboard visuals. |
      """)

    html =
      render_component(&ChatMessage.chat_message/1,
        message: message,
        markdown_renderer: &Markdown.render/1
      )

    assert html =~ "<table>"
    assert html =~ "<th>Intent</th>"
    assert html =~ "<td>notify</td>"
    refute html =~ "| Intent | Definition | Response expected | Example |"
  end

  test "renders fenced code blocks with github-light syntax highlighting" do
    message =
      DisplayMessage.assistant("""
      ```elixir
      IO.puts(\"hi\")
      ```
      """)

    html =
      render_component(&ChatMessage.chat_message/1,
        message: message,
        markdown_renderer: &Markdown.render/1
      )

    assert html =~ ~s(class="lumis")
    assert html =~ ~s(class="language-elixir")
    assert html =~ "#1f2328"
    refute html =~ "#282c34"
  end
end
