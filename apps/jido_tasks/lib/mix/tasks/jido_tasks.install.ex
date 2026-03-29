defmodule Mix.Tasks.JidoTasks.Install do
  @shortdoc "Generates jido_tasks migration file"
  @moduledoc """
  Generates the migration file for the jido_tasks database table.

      $ mix jido_tasks.install

  Creates a migration for the `jido_tasks` table.

  The migration includes a foreign key reference to `jido_murmur_workspaces`.
  Ensure jido_murmur migrations have been run first.

  Existing migrations are detected by module name and skipped.
  """

  use Mix.Task

  import Mix.Generator

  @migrations [
    {1, "create_jido_tasks"}
  ]

  @impl true
  def run(_args) do
    migrations_path = get_migrations_path()
    File.mkdir_p!(migrations_path)
    existing = existing_migration_names(migrations_path)

    migration_module = migration_module_prefix()

    for {offset, name} <- @migrations do
      if name in existing do
        Mix.shell().info("Migration #{name} already exists, skipping.")
      else
        timestamp = generate_timestamp(offset)
        source = template_path(name)
        target = Path.join(migrations_path, "#{timestamp}_#{name}.exs")

        content = EEx.eval_file(source, assigns: %{migration_module: migration_module})
        create_file(target, content)
      end
    end

    Mix.shell().info("""

    Ensure jido_murmur migrations are run first (jido_tasks references jido_murmur_workspaces).

    Then run:

        $ mix ecto.migrate
    """)
  end

  defp get_migrations_path do
    if File.dir?("priv/repo/migrations") do
      "priv/repo/migrations"
    else
      Path.join(["priv", "repo", "migrations"])
    end
  end

  defp migration_module_prefix do
    case Mix.Project.config()[:app] do
      nil -> "MyApp.Repo.Migrations"
      app -> app |> to_string() |> Macro.camelize() |> then(&"#{&1}.Repo.Migrations")
    end
  end

  defp template_path(name) do
    Application.app_dir(:jido_tasks, "priv/templates/#{name}.exs")
  end

  defp generate_timestamp(offset) do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    total_seconds = :calendar.datetime_to_gregorian_seconds({{y, m, d}, {hh, mm, ss}}) + offset
    {{y2, m2, d2}, {hh2, mm2, ss2}} = :calendar.gregorian_seconds_to_datetime(total_seconds)

    "#{y2}#{pad(m2)}#{pad(d2)}#{pad(hh2)}#{pad(mm2)}#{pad(ss2)}"
  end

  defp pad(i) when i < 10, do: "0#{i}"
  defp pad(i), do: "#{i}"

  defp existing_migration_names(path) do
    if File.dir?(path) do
      path
      |> File.ls!()
      |> Enum.map(fn filename ->
        filename
        |> String.replace(~r/^\d{14}_/, "")
        |> String.trim_trailing(".exs")
      end)
      |> MapSet.new()
    else
      MapSet.new()
    end
  end
end
