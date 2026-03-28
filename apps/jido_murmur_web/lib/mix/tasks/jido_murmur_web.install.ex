defmodule Mix.Tasks.JidoMurmurWeb.Install do
  @shortdoc "Copies jido_murmur_web component files into your project"
  @moduledoc """
  Copies jido_murmur_web component source files into your project
  for full customization.

      $ mix jido_murmur_web.install chat
      $ mix jido_murmur_web.install workspace
      $ mix jido_murmur_web.install artifacts
      $ mix jido_murmur_web.install all

  ## Component Groups

    * `chat` — ChatMessage, ChatStream, MessageInput, StreamingIndicator
    * `workspace` — WorkspaceList, AgentSelector, AgentHeader
    * `artifacts` — ArtifactPanel (includes Generic, PaperList, PdfViewer sub-renderers)
    * `all` — All components from all groups

  Components are copied into `lib/<app>_web/components/` with your
  application's module namespace substituted in.
  """

  use Mix.Task

  import Mix.Generator

  @component_groups %{
    "chat" => ~w(chat_message chat_stream message_input streaming_indicator),
    "workspace" => ~w(workspace_list agent_selector agent_header),
    "artifacts" => ~w(artifact_panel)
  }

  @impl true
  def run([]) do
    Mix.shell().error("Usage: mix jido_murmur_web.install <group>\n\nGroups: chat, workspace, artifacts, all")
    exit({:shutdown, 1})
  end

  def run([group]) do
    components = resolve_group(group)
    app_module = app_module_name()
    target_dir = component_target_dir()

    File.mkdir_p!(target_dir)

    for component <- components do
      source = template_path(component)

      unless File.exists?(source) do
        Mix.shell().error("Template not found: #{source}")
        exit({:shutdown, 1})
      end

      target = Path.join(target_dir, "#{component}.ex")

      if File.exists?(target) do
        Mix.shell().info("#{component}.ex already exists, skipping.")
      else
        content = EEx.eval_file(source, assigns: %{app_module: app_module})
        create_file(target, content)
      end
    end

    Mix.shell().info("""

    Components copied to #{target_dir}/

    Import them in your LiveView:

        import #{app_module}Web.Components.ChatMessage
        import #{app_module}Web.Components.ChatStream
        # ... etc
    """)
  end

  def run(_args) do
    Mix.shell().error("Usage: mix jido_murmur_web.install <group>\n\nGroups: chat, workspace, artifacts, all")
    exit({:shutdown, 1})
  end

  defp resolve_group("all") do
    @component_groups
    |> Map.values()
    |> List.flatten()
  end

  defp resolve_group(group) when is_map_key(@component_groups, group) do
    Map.fetch!(@component_groups, group)
  end

  defp resolve_group(group) do
    Mix.shell().error("Unknown group: #{group}\n\nAvailable groups: chat, workspace, artifacts, all")
    exit({:shutdown, 1})
  end

  defp app_module_name do
    case Mix.Project.config()[:app] do
      nil -> "MyApp"
      app -> app |> to_string() |> Macro.camelize()
    end
  end

  defp component_target_dir do
    app = Mix.Project.config()[:app] || :my_app
    Path.join(["lib", "#{app}_web", "components"])
  end

  defp template_path(component) do
    Application.app_dir(:jido_murmur_web, "priv/templates/components/#{component}.ex")
  end
end
