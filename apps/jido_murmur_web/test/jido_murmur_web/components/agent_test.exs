defmodule JidoMurmurWeb.Components.AgentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias JidoMurmurWeb.Components.StreamingIndicator
  alias JidoMurmurWeb.Components.AgentHeader
  alias JidoMurmurWeb.Components.AgentSelector

  describe "StreamingIndicator.streaming_indicator/1" do
    test "renders nothing when idle" do
      html = render_component(&StreamingIndicator.streaming_indicator/1, status: :idle)

      refute html =~ "loading"
      refute html =~ "Streaming"
    end

    test "renders thinking state when busy without content" do
      html = render_component(&StreamingIndicator.streaming_indicator/1, status: :busy)

      assert html =~ "loading loading-dots"
      assert html =~ "Thinking..."
    end

    test "renders streaming state when busy with content" do
      stream = %{content: "some output", thinking: "", tool_calls: []}

      html = render_component(&StreamingIndicator.streaming_indicator/1, status: :busy, stream: stream)

      assert html =~ "Streaming..."
    end

    test "renders streaming state when busy with thinking" do
      stream = %{content: "", thinking: "processing...", tool_calls: []}

      html = render_component(&StreamingIndicator.streaming_indicator/1, status: :busy, stream: stream)

      assert html =~ "Streaming..."
    end
  end

  describe "AgentHeader.agent_header/1" do
    test "renders agent name and profile" do
      session = %{id: "sess-1", display_name: "Research Bot", agent_profile_id: "general"}
      color = %{dot: "bg-blue-500", header: "border-blue-500/20 bg-blue-500/5"}

      html = render_component(&AgentHeader.agent_header/1, session: session, color: color)

      assert html =~ "Research Bot"
      assert html =~ "general"
      assert html =~ "bg-blue-500"
    end

    test "shows busy indicator when busy" do
      session = %{id: "sess-2", display_name: "Bot", agent_profile_id: "gen"}
      color = %{dot: "bg-blue-500", header: "border-blue-500/20"}

      html = render_component(&AgentHeader.agent_header/1, session: session, color: color, status: :busy)

      assert html =~ "loading loading-dots"
    end

    test "does not show busy indicator when idle" do
      session = %{id: "sess-3", display_name: "Bot", agent_profile_id: "gen"}
      color = %{dot: "bg-blue-500", header: "border-blue-500/20"}

      html = render_component(&AgentHeader.agent_header/1, session: session, color: color, status: :idle)

      refute html =~ "loading loading-dots"
    end

    test "renders remove button with session id" do
      session = %{id: "sess-4", display_name: "Bot", agent_profile_id: "gen"}
      color = %{dot: "bg-blue-500", header: "border-blue-500/20"}

      html = render_component(&AgentHeader.agent_header/1, session: session, color: color)

      assert html =~ "remove_agent"
      assert html =~ "sess-4"
    end

    test "uses custom on_remove event" do
      session = %{id: "sess-5", display_name: "Bot", agent_profile_id: "gen"}
      color = %{dot: "bg-blue-500", header: "border-blue-500/20"}

      html = render_component(&AgentHeader.agent_header/1, session: session, color: color, on_remove: "delete_agent")

      assert html =~ "delete_agent"
    end
  end

  describe "AgentSelector.agent_selector/1" do
    test "renders dialog with profile options" do
      profiles = [
        %{id: "general", description: "General assistant"},
        %{id: "arxiv", description: "Research assistant"}
      ]

      form = Phoenix.Component.to_form(%{"profile_id" => "", "display_name" => ""}, as: :agent)

      html = render_component(&AgentSelector.agent_selector/1, profiles: profiles, form: form)

      assert html =~ "add-agent-dialog"
      assert html =~ "general"
      assert html =~ "General assistant"
      assert html =~ "arxiv"
      assert html =~ "Research assistant"
      assert html =~ "Add Agent to Workspace"
    end

    test "renders with custom dialog id" do
      profiles = [%{id: "gen", description: "Gen"}]
      form = Phoenix.Component.to_form(%{"profile_id" => "", "display_name" => ""}, as: :agent)

      html = render_component(&AgentSelector.agent_selector/1, profiles: profiles, form: form, dialog_id: "custom-dialog")

      assert html =~ "custom-dialog"
    end

    test "renders with custom submit event" do
      profiles = [%{id: "gen", description: "Gen"}]
      form = Phoenix.Component.to_form(%{"profile_id" => "", "display_name" => ""}, as: :agent)

      html = render_component(&AgentSelector.agent_selector/1, profiles: profiles, form: form, on_submit: "create_agent")

      assert html =~ "create_agent"
    end
  end
end
