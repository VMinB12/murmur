defmodule Mix.Tasks.JidoMurmurWeb.InstallTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  @moduletag :tmp_dir

  describe "jido_murmur_web.install" do
    test "copies chat group components", %{tmp_dir: tmp_dir} do
      in_project(tmp_dir, fn ->
        output = capture_io(fn -> Mix.Tasks.JidoMurmurWeb.Install.run(["chat"]) end)

        assert output =~ "chat_message.ex"
        assert output =~ "chat_stream.ex"
        assert output =~ "message_input.ex"
        assert output =~ "streaming_indicator.ex"

        target_dir = Path.join(tmp_dir, "lib/jido_murmur_web_web/components")
        assert File.dir?(target_dir)

        chat_message = File.read!(Path.join(target_dir, "chat_message.ex"))
        assert chat_message =~ "JidoMurmurWebWeb.Components.ChatMessage"
        refute chat_message =~ "<%= @app_module %>"
      end)
    end

    test "copies workspace group components", %{tmp_dir: tmp_dir} do
      in_project(tmp_dir, fn ->
        output = capture_io(fn -> Mix.Tasks.JidoMurmurWeb.Install.run(["workspace"]) end)

        assert output =~ "workspace_list.ex"
        assert output =~ "agent_selector.ex"
        assert output =~ "agent_header.ex"
      end)
    end

    test "copies artifacts group components", %{tmp_dir: tmp_dir} do
      in_project(tmp_dir, fn ->
        output = capture_io(fn -> Mix.Tasks.JidoMurmurWeb.Install.run(["artifacts"]) end)

        assert output =~ "artifact_panel.ex"
      end)
    end

    test "copies all components with 'all' group", %{tmp_dir: tmp_dir} do
      in_project(tmp_dir, fn ->
        output = capture_io(fn -> Mix.Tasks.JidoMurmurWeb.Install.run(["all"]) end)

        assert output =~ "chat_message.ex"
        assert output =~ "chat_stream.ex"
        assert output =~ "message_input.ex"
        assert output =~ "streaming_indicator.ex"
        assert output =~ "workspace_list.ex"
        assert output =~ "agent_selector.ex"
        assert output =~ "agent_header.ex"
        assert output =~ "artifact_panel.ex"
      end)
    end

    test "skips existing files", %{tmp_dir: tmp_dir} do
      in_project(tmp_dir, fn ->
        target_dir = Path.join(tmp_dir, "lib/jido_murmur_web_web/components")
        File.mkdir_p!(target_dir)
        File.write!(Path.join(target_dir, "chat_message.ex"), "# existing")

        output = capture_io(fn -> Mix.Tasks.JidoMurmurWeb.Install.run(["chat"]) end)

        assert output =~ "chat_message.ex already exists, skipping"
        # Should still copy the others
        assert output =~ "chat_stream.ex"

        # Verify original content was preserved
        assert File.read!(Path.join(target_dir, "chat_message.ex")) == "# existing"
      end)
    end

    test "substitutes module namespace", %{tmp_dir: tmp_dir} do
      in_project(tmp_dir, fn ->
        capture_io(fn -> Mix.Tasks.JidoMurmurWeb.Install.run(["workspace"]) end)

        target_dir = Path.join(tmp_dir, "lib/jido_murmur_web_web/components")
        workspace_list = File.read!(Path.join(target_dir, "workspace_list.ex"))

        # Should have the app module substituted
        assert workspace_list =~ "JidoMurmurWebWeb.Components.WorkspaceList"
        assert workspace_list =~ "JidoMurmurWebWeb.CoreComponents"
      end)
    end
  end

  defp in_project(tmp_dir, fun) do
    # Create a minimal mix.exs in the tmp dir to simulate a project
    mix_exs = """
    defmodule JidoMurmurWebWeb.MixProject do
      use Mix.Project
      def project, do: [app: :jido_murmur_web, version: "0.1.0"]
    end
    """

    File.write!(Path.join(tmp_dir, "mix.exs"), mix_exs)

    # Run in the tmp dir context
    old_dir = File.cwd!()
    File.cd!(tmp_dir)

    try do
      fun.()
    after
      File.cd!(old_dir)
    end
  end
end
