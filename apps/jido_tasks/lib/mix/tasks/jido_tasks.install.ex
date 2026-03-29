if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.JidoTasks.Install do
    @shortdoc "Installs jido_tasks: generates migration, adds config, chains jido_murmur if needed"
    @moduledoc """
    Installs and configures jido_tasks in your project.

        $ mix jido_tasks.install

    This task will:

    1. Check if `:jido_murmur` is configured — if not, chains `jido_murmur.install` first
    2. Generate the `create_jido_tasks` migration
    3. Add `:jido_tasks` config block to `config/config.exs`

    Pass `--yes` to apply changes without prompting.

    Existing migrations and config are detected and skipped (idempotent).
    """

    use Igniter.Mix.Task

    alias Igniter.Libs.Ecto, as: IgniterEcto
    alias Igniter.Project.Application, as: IgniterApp
    alias Igniter.Project.Config, as: IgniterConfig

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :jido_tasks,
        adds_deps: [],
        installs: [],
        composes: ["jido_murmur.install"],
        example: "mix jido_tasks.install"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      app_name = IgniterApp.app_name(igniter)
      app_module_base = app_name |> to_string() |> Macro.camelize()
      repo_module = Module.concat([app_module_base, "Repo"])

      igniter
      |> maybe_chain_jido_murmur()
      |> generate_migration(repo_module)
      |> inject_config(app_module_base)
      |> Igniter.add_notice("""
      jido_tasks installed!

      Run migrations:

          mix ecto.migrate
      """)
    end

    defp maybe_chain_jido_murmur(igniter) do
      if IgniterConfig.configures_key?(igniter, "config.exs", :jido_murmur, [:repo]) do
        igniter
      else
        Igniter.compose_task(igniter, "jido_murmur.install")
      end
    end

    defp generate_migration(igniter, repo_module) do
      body = """
      def change do
        create table(:jido_tasks, primary_key: false) do
          add :id, :binary_id, primary_key: true
          add :workspace_id, references(:jido_murmur_workspaces, type: :binary_id, on_delete: :delete_all), null: false
          add :title, :string, null: false, size: 200
          add :description, :string, size: 2000
          add :assignee, :string, null: false
          add :status, :string, null: false, default: "todo"
          add :created_by, :string, null: false
          add :owner_id, :string
          add :metadata, :map, default: %{}

          timestamps(type: :utc_datetime_usec)
        end

        create index(:jido_tasks, [:workspace_id])
        create index(:jido_tasks, [:workspace_id, :status])
      end
      """

      IgniterEcto.gen_migration(igniter, repo_module, "create_jido_tasks",
        body: body,
        on_exists: :skip
      )
    end

    defp inject_config(igniter, app_module_base) do
      repo = Module.concat([app_module_base, "Repo"])
      pubsub = Module.concat([app_module_base, "PubSub"])

      igniter
      |> IgniterConfig.configure_new(
        "config.exs",
        :jido_tasks,
        [:repo],
        {:code, Sourceror.parse_string!("#{inspect(repo)}")}
      )
      |> IgniterConfig.configure_new(
        "config.exs",
        :jido_tasks,
        [:pubsub],
        {:code, Sourceror.parse_string!("#{inspect(pubsub)}")}
      )
    end
  end
else
  defmodule Mix.Tasks.JidoTasks.Install do
    @shortdoc "Installs jido_tasks (requires Igniter)"
    @moduledoc """
    Installs jido_tasks. Requires the Igniter package.

    Add `{:igniter, "~> 0.7"}` to your deps in mix.exs, then re-run:

        mix jido_tasks.install
    """

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      ** (Mix) This install task requires the Igniter package.

      Add {:igniter, "~> 0.7"} to your deps in mix.exs, then re-run:

          mix jido_tasks.install

      For manual setup instructions, see:
      https://hexdocs.pm/jido_tasks/installation.html
      """)

      exit({:shutdown, 1})
    end
  end
end
