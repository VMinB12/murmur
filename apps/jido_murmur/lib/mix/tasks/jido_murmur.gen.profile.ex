if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.JidoMurmur.Gen.Profile do
    @shortdoc "Generates a jido_murmur agent profile module"
    @moduledoc """
    Generates a new agent profile module.

        $ mix jido_murmur.gen.profile ResearchAssistant

    Creates `lib/{app}/agents/profiles/research_assistant.ex` with:

      * `use Jido.AI.Agent` boilerplate
      * Default tools (`JidoMurmur.TellAction`)
      * Default plugins (`JidoMurmur.StreamingPlugin`, `JidoArtifacts.ArtifactPlugin`)
      * Placeholder system prompt
      * `catalog_meta/0` function

    Pass `--yes` to apply changes without prompting.
    """

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :jido_murmur,
        adds_deps: [],
        installs: [],
        positional: [:name],
        example: "mix jido_murmur.gen.profile ResearchAssistant"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      name = igniter.args.positional[:name]

      unless name do
        raise "Usage: mix jido_murmur.gen.profile <Name>\n\nExample: mix jido_murmur.gen.profile ResearchAssistant"
      end

      app_name = Igniter.Project.Application.app_name(igniter)
      app_module_base = app_name |> to_string() |> Macro.camelize()

      module = Module.concat([app_module_base, "Agents", "Profiles", name])
      underscore_name = Macro.underscore(name)

      contents = """
        @moduledoc "#{name} agent profile."
        @behaviour JidoMurmur.AgentProfile

        use Jido.AI.Agent,
          name: "#{underscore_name}",
          description: "A #{underscore_name |> String.replace("_", " ")} agent",
          model: :fast,
          tools: [
            JidoMurmur.TellAction,
            JidoTasks.Tools.AddTask,
            JidoTasks.Tools.UpdateTask,
            JidoTasks.Tools.ListTasks
          ],
          plugins: [JidoMurmur.StreamingPlugin, JidoArtifacts.ArtifactPlugin],
          request_transformer: JidoMurmur.MessageInjector,
          system_prompt: \\"\\"\\"
          You are a helpful #{underscore_name |> String.replace("_", " ")}.
          \\"\\"\\"

        @impl JidoMurmur.AgentProfile
        def catalog_meta, do: %{color: "blue"}
      """

      Igniter.Project.Module.create_module(igniter, module, contents)
    end
  end
else
  defmodule Mix.Tasks.JidoMurmur.Gen.Profile do
    @shortdoc "Generates a jido_murmur agent profile (requires Igniter)"
    @moduledoc """
    Generates an agent profile module. Requires the Igniter package.

    Add `{:igniter, "~> 0.7"}` to your deps in mix.exs, then re-run:

        mix jido_murmur.gen.profile ResearchAssistant
    """

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      ** (Mix) This generator requires the Igniter package.

      Add {:igniter, "~> 0.7"} to your deps in mix.exs, then re-run:

          mix jido_murmur.gen.profile <Name>

      For manual setup instructions, see:
      https://hexdocs.pm/jido_murmur/installation.html
      """)

      exit({:shutdown, 1})
    end
  end
end
