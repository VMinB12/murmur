if Code.ensure_loaded?(Igniter) do
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

      * `chat` — ChatMessage, MessageInput, StreamingIndicator
      * `workspace` — WorkspaceList, AgentSelector, AgentHeader
      * `artifacts` — ArtifactPanel with Generic fallback renderer
      * `all` — All components from all groups

    Components are copied into `lib/<app>_web/components/jido_murmur/` with your
    application's module namespace substituted in.

    Existing files are skipped (idempotent).
    """

    use Mix.Task

    import Mix.Generator

    @component_groups %{
      "chat" => [
        %{template: "chat_message.ex", target: "chat_message.ex"},
        %{template: "message_input.ex", target: "message_input.ex"},
        %{template: "streaming_indicator.ex", target: "streaming_indicator.ex"}
      ],
      "workspace" => [
        %{template: "workspace_list.ex", target: "workspace_list.ex"},
        %{template: "agent_selector.ex", target: "agent_selector.ex"},
        %{template: "agent_header.ex", target: "agent_header.ex"}
      ],
      "artifacts" => [
        %{template: "artifact_panel.ex", target: "artifact_panel.ex"},
        %{template: Path.join("artifact_panel", "generic.ex"), target: Path.join("artifact_panel", "generic.ex")}
      ]
    }

    @impl Mix.Task
    def run([]) do
      Mix.shell().error("Usage: mix jido_murmur_web.install <group>\n\nGroups: chat, workspace, artifacts, all")
      exit({:shutdown, 1})
    end

    def run([group]) do
      components = resolve_group(group)
      app_name = Igniter.Project.Application.app_name(Igniter.new())
      app_module = app_name |> to_string() |> Macro.camelize()
      target_dir = Path.join(["lib", "#{app_name}_web", "components", "jido_murmur"])

      File.mkdir_p!(target_dir)

      for %{template: template, target: relative_target} <- components do
        source = template_path(template)
        target = Path.join(target_dir, relative_target)

        target
        |> Path.dirname()
        |> File.mkdir_p!()

        if File.exists?(target) do
          Mix.shell().info("#{relative_target} already exists, skipping.")
        else
          contents = EEx.eval_file(source, assigns: %{app_module: app_module})
          create_file(target, contents)
        end
      end

      Mix.shell().info("""

      Components copied to #{target_dir}/

      Import them in your LiveView or add to your app's html_helpers:

          import #{app_module}Web.Components.ChatMessage
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

    defp template_path(component) do
      Application.app_dir(:jido_murmur_web, Path.join("priv/templates/components", component))
    end
  end
else
  defmodule Mix.Tasks.JidoMurmurWeb.Install do
    @shortdoc "Copies jido_murmur_web components (requires Igniter)"
    @moduledoc """
    Copies jido_murmur_web component files. Requires the Igniter package.

    Add `{:igniter, "~> 0.7"}` to your deps in mix.exs, then re-run:

        mix jido_murmur_web.install all
    """

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      ** (Mix) This install task requires the Igniter package.

      Add {:igniter, "~> 0.7"} to your deps in mix.exs, then re-run:

          mix jido_murmur_web.install all

      For manual setup instructions, see:
      https://hexdocs.pm/jido_murmur_web/installation.html
      """)

      exit({:shutdown, 1})
    end
  end
end
