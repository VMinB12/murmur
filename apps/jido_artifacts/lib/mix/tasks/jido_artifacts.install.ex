if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.JidoArtifacts.Install do
    @shortdoc "Installs jido_artifacts configuration"
    @moduledoc """
    Installs jido_artifacts configuration into the host application.

        $ mix jido_artifacts.install

    Adds `config :jido_artifacts, pubsub: {App}.PubSub` to config.

    Pass `--yes` to apply changes without prompting.

    Existing config is detected and skipped (idempotent).
    """

    use Igniter.Mix.Task

    alias Igniter.Project.Application, as: IgniterApp
    alias Igniter.Project.Config, as: IgniterConfig

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :jido_artifacts,
        adds_deps: [],
        installs: [],
        example: "mix jido_artifacts.install"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      app_name = IgniterApp.app_name(igniter)
      app_module_base = app_name |> to_string() |> Macro.camelize()
      pubsub = Module.concat([app_module_base, "PubSub"])

      igniter
      |> IgniterConfig.configure_new(
        "config.exs",
        :jido_artifacts,
        [:pubsub],
        {:code, Sourceror.parse_string!("#{inspect(pubsub)}")}
      )
      |> Igniter.add_notice("""
      jido_artifacts installed!

      Config added to config/config.exs.
      """)
    end
  end
else
  defmodule Mix.Tasks.JidoArtifacts.Install do
    @shortdoc "Installs jido_artifacts configuration (requires Igniter)"
    @moduledoc """
    Installs jido_artifacts. Requires the Igniter package.

    Add `{:igniter, "~> 0.7"}` to your deps in mix.exs, then re-run:

        mix jido_artifacts.install
    """

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      ** (Mix) This install task requires the Igniter package.

      Add {:igniter, "~> 0.7"} to your deps in mix.exs, then re-run:

          mix jido_artifacts.install

      For manual setup instructions, see:
      https://hexdocs.pm/jido_artifacts/installation.html
      """)

      exit({:shutdown, 1})
    end
  end
end
