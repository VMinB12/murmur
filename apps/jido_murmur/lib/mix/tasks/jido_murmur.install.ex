if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.JidoMurmur.Install do
    @shortdoc "Installs jido_murmur: generates migrations, adds config, adds supervisor"
    @moduledoc """
    Installs and configures jido_murmur in your project.

        $ mix jido_murmur.install

    This task will:

    1. Generate migrations for jido_murmur database tables
    2. Add `:jido_murmur` config block to `config/config.exs`
    3. Add `JidoMurmur.Supervisor` to your application supervision tree

    Pass `--yes` to apply changes without prompting.

    Existing migrations and config are detected and skipped (idempotent).
    """

    use Igniter.Mix.Task

    alias Igniter.Libs.Ecto, as: IgniterEcto
    alias Igniter.Project.Application, as: IgniterApp
    alias Igniter.Project.Config, as: IgniterConfig

    @migrations [
      {"create_jido_murmur_workspaces",
       """
       def change do
         create table(:jido_murmur_workspaces, primary_key: false) do
           add :id, :binary_id, primary_key: true
           add :name, :string, null: false
           add :owner_id, :string
           add :metadata, :map, default: %{}

           timestamps(type: :utc_datetime_usec)
         end

         create index(:jido_murmur_workspaces, [:owner_id])
       end
       """},
      {"create_jido_murmur_agent_sessions",
       """
       def change do
         create table(:jido_murmur_agent_sessions, primary_key: false) do
           add :id, :binary_id, primary_key: true
           add :workspace_id, references(:jido_murmur_workspaces, type: :binary_id, on_delete: :delete_all), null: false
           add :agent_profile_id, :string, null: false
           add :display_name, :string, null: false
           add :status, :string, default: "idle", null: false
           add :owner_id, :string
           add :metadata, :map, default: %{}

           timestamps(type: :utc_datetime_usec)
         end

         create index(:jido_murmur_agent_sessions, [:workspace_id])
         create unique_index(:jido_murmur_agent_sessions, [:workspace_id, :display_name])
       end
       """},
      {"create_jido_murmur_checkpoints",
       """
       def change do
         create table(:jido_murmur_checkpoints, primary_key: false) do
           add :key, :string, primary_key: true
           add :data, :map, null: false

           timestamps(type: :utc_datetime_usec)
         end
       end
       """},
      {"create_jido_murmur_thread_entries",
       """
       def change do
         create table(:jido_murmur_thread_entries, primary_key: false) do
           add :id, :binary_id, primary_key: true
           add :thread_id, :string, null: false
           add :seq, :integer, null: false
           add :kind, :string, null: false
           add :payload, :map, default: %{}
           add :refs, :map, default: %{}
           add :at, :bigint, null: false

           timestamps(type: :utc_datetime_usec, updated_at: false)
         end

         create unique_index(:jido_murmur_thread_entries, [:thread_id, :seq])
         create index(:jido_murmur_thread_entries, [:thread_id])
       end
       """}
    ]

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :jido_murmur,
        adds_deps: [],
        installs: [],
        example: "mix jido_murmur.install"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      app_name = IgniterApp.app_name(igniter)
      app_module_base = app_name |> to_string() |> Macro.camelize()
      repo_module = Module.concat([app_module_base, "Repo"])

      igniter
      |> generate_migrations(repo_module)
      |> inject_config(app_name, app_module_base)
      |> add_supervisor()
      |> Igniter.add_notice("""
      jido_murmur installed!

      Run migrations:

          mix ecto.migrate
      """)
    end

    defp generate_migrations(igniter, repo_module) do
      Enum.reduce(@migrations, igniter, fn {name, body}, igniter ->
        IgniterEcto.gen_migration(igniter, repo_module, name, body: body, on_exists: :skip)
      end)
    end

    defp inject_config(igniter, app_name, app_module_base) do
      repo = Module.concat([app_module_base, "Repo"])
      pubsub = Module.concat([app_module_base, "PubSub"])
      jido_mod = Module.concat([app_module_base, "Jido"])

      IgniterConfig.configure_new(
        igniter,
        "config.exs",
        :jido_murmur,
        [:repo],
        {:code, Sourceror.parse_string!("#{inspect(repo)}")}
      )
      |> IgniterConfig.configure_new(
        "config.exs",
        :jido_murmur,
        [:pubsub],
        {:code, Sourceror.parse_string!("#{inspect(pubsub)}")}
      )
      |> IgniterConfig.configure_new(
        "config.exs",
        :jido_murmur,
        [:jido_mod],
        {:code, Sourceror.parse_string!("#{inspect(jido_mod)}")}
      )
      |> IgniterConfig.configure_new(
        "config.exs",
        :jido_murmur,
        [:otp_app],
        app_name
      )
    end

    defp add_supervisor(igniter) do
      IgniterApp.add_new_child(
        igniter,
        JidoMurmur.Supervisor,
        after: [Ecto.Repo, Phoenix.PubSub]
      )
    end
  end
else
  defmodule Mix.Tasks.JidoMurmur.Install do
    @shortdoc "Installs jido_murmur (requires Igniter)"
    @moduledoc """
    Installs jido_murmur. Requires the Igniter package.

    Add `{:igniter, "~> 0.7"}` to your deps in mix.exs, then re-run:

        mix jido_murmur.install
    """

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      ** (Mix) This install task requires the Igniter package.

      Add {:igniter, "~> 0.7"} to your deps in mix.exs, then re-run:

          mix jido_murmur.install

      For manual setup instructions, see:
      https://hexdocs.pm/jido_murmur/installation.html
      """)

      exit({:shutdown, 1})
    end
  end
end
