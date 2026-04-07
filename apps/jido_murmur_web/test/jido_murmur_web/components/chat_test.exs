defmodule JidoMurmurWeb.Components.ChatTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias JidoMurmur.ActorIdentity
  alias JidoMurmur.DisplayMessage.ToolCall
  alias JidoMurmur.HiddenContent
  alias JidoMurmurWeb.Components.ChatMessage
  alias JidoMurmurWeb.Components.MessageInput

  describe "ChatMessage.chat_message/1" do
    test "renders user message with primary styling" do
      message = %{
        id: "msg-1",
        role: "user",
        content: "Hello, agent!",
        actor: ActorIdentity.human()
      }

      html = render_component(&ChatMessage.chat_message/1, message: message)

      assert html =~ "Hello, agent!"
      assert html =~ "You"
      assert html =~ "bg-primary"
      assert html =~ "chat-bubble"
      assert html =~ "msg-msg-1"
    end

    test "renders assistant message with base styling" do
      message = %{
        id: "msg-2",
        role: "assistant",
        content: "I can help with that.",
        sender_name: nil
      }

      html = render_component(&ChatMessage.chat_message/1, message: message)

      assert html =~ "I can help with that."
      assert html =~ "bg-base-200"
      assert html =~ "chat-start"
      assert html =~ "msg-msg-2"
    end

    test "renders thinking trace" do
      message = %{
        id: "msg-3",
        role: "assistant",
        content: "Result here",
        sender_name: nil,
        thinking: "Let me analyze this..."
      }

      html = render_component(&ChatMessage.chat_message/1, message: message)

      assert html =~ "Let me analyze this..."
      assert html =~ "Thinking..."
      assert html =~ "hero-light-bulb"
      assert html =~ "collapse"
    end

    test "renders tool calls" do
      message = %{
        id: "msg-4",
        role: "assistant",
        content: "",
        sender_name: nil,
        tool_calls: [
          %{name: "arxiv_search", result: "Found 5 papers", status: :completed},
          %{name: "add_task", result: "Error: invalid params", status: :error}
        ]
      }

      html = render_component(&ChatMessage.chat_message/1, message: message)

      assert html =~ "arxiv_search"
      assert html =~ "Completed"
      assert html =~ "add_task"
      assert html =~ "Error"
    end

    test "renders running assistant cursor for in-progress turns" do
      message = %{
        id: "msg-running",
        role: "assistant",
        content: "Still working",
        sender_name: nil,
        status: :running
      }

      html = render_component(&ChatMessage.chat_message/1, message: message)

      assert html =~ "Still working"
      assert html =~ "animate-pulse"
    end

    test "renders canonical tool call structs without Access errors" do
      message = %{
        id: "msg-struct-tool-call",
        role: "assistant",
        content: "",
        sender_name: nil,
        tool_calls: [
          %ToolCall{
            id: "call-1",
            name: "tell",
            args: %{"target_agent" => "bob", "intent" => "notify", "message" => "Hi"},
            result: ~s({"ok":true}),
            status: :completed
          }
        ]
      }

      html = render_component(&ChatMessage.chat_message/1, message: message)

      assert html =~ "tell"
      assert html =~ "target_agent"
      assert html =~ ~s({&quot;ok&quot;:true})
    end

    test "renders usage tooltip" do
      message = %{
        id: "msg-5",
        role: "assistant",
        content: "Done!",
        sender_name: nil,
        usage: %{input_tokens: 100, output_tokens: 50, total_tokens: 150, model: "gpt-4", duration_ms: 1500.0}
      }

      html = render_component(&ChatMessage.chat_message/1, message: message)

      assert html =~ "100 in"
      assert html =~ "50 out"
      assert html =~ "150 total"
      assert html =~ "gpt-4"
      assert html =~ "1.5s"
    end

    test "applies inter-agent color when color is provided" do
      message = %{
        id: "msg-6",
        role: "user",
        content: "Cross-agent message",
        actor: ActorIdentity.agent("ResearchBot")
      }

      color = %{dot: "bg-blue-500", text: "text-blue-500", bg: "bg-blue-500/10", header: ""}

      html = render_component(&ChatMessage.chat_message/1, message: message, color: color)

      assert html =~ "bg-blue-500"
      assert html =~ "Cross-agent message"
    end

    test "uses markdown renderer when provided" do
      message = %{
        id: "msg-7",
        role: "assistant",
        content: "**bold text**",
        sender_name: nil
      }

      renderer = fn text -> Phoenix.HTML.raw("<strong>#{text}</strong>") end

      html = render_component(&ChatMessage.chat_message/1, message: message, markdown_renderer: renderer)

      assert html =~ "<strong>**bold text**</strong>"
    end

    test "renders hidden-envelope programmatic user messages through markdown" do
      message = %{
        id: "msg-tell-markdown",
        role: "user",
        content: HiddenContent.wrap_markdown("**bold tell**", sender: "ResearchBot", intent: "notify"),
        actor: ActorIdentity.agent("ResearchBot")
      }

      renderer = fn text ->
        text
        |> MDEx.to_html!()
        |> Phoenix.HTML.raw()
      end

      html = render_component(&ChatMessage.chat_message/1, message: message, markdown_renderer: renderer)

      assert html =~ "<strong>bold tell</strong>"
      refute html =~ "&lt;!-- murmur:"
      refute html =~ "sender&quot;:&quot;ResearchBot&quot;"
    end

    test "keeps direct human messages as raw text even if they match the hidden-envelope format" do
      message = %{
        id: "msg-human-raw",
        role: "user",
        content: HiddenContent.wrap_markdown("**not markdown rendered**", sender: "Alice", intent: "notify"),
        actor: ActorIdentity.human()
      }

      renderer = fn text ->
        text
        |> MDEx.to_html!()
        |> Phoenix.HTML.raw()
      end

      html = render_component(&ChatMessage.chat_message/1, message: message, markdown_renderer: renderer)

      assert html =~ "&lt;!-- murmur:"
      assert html =~ "**not markdown rendered**"
      refute html =~ "<strong>not markdown rendered</strong>"
    end

    test "handles empty content gracefully" do
      message = %{
        id: "msg-8",
        role: "assistant",
        content: "",
        sender_name: nil
      }

      html = render_component(&ChatMessage.chat_message/1, message: message)

      refute html =~ "bg-base-200"
    end
  end

  describe "MessageInput.message_input/1" do
    test "renders form with session_id hidden field" do
      html = render_component(&MessageInput.message_input/1, id: "msg-form-1", session_id: "session-abc")

      assert html =~ "msg-form-1"
      assert html =~ ~s(value="session-abc")
      assert html =~ "message[session_id]"
      assert html =~ "message[content]"
      assert html =~ "phx-hook="
    end

    test "renders form without session_id when nil" do
      html = render_component(&MessageInput.message_input/1, id: "unified-form")

      assert html =~ "unified-form"
      refute html =~ "message[session_id]"
    end

    test "renders custom placeholder" do
      html = render_component(&MessageInput.message_input/1, id: "form-1", placeholder: "Ask anything...")

      assert html =~ "Ask anything..."
    end

    test "renders custom submit event" do
      html = render_component(&MessageInput.message_input/1, id: "form-1", on_submit: "send_unified_message")

      assert html =~ "send_unified_message"
    end
  end
end
