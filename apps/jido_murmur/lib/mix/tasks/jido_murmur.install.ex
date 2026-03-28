defmodule Mix.Tasks.JidoMurmur.Install do
  @shortdoc "Generates jido_murmur migration files"
  @moduledoc """
  Generates migration files for jido_murmur database tables.

      $ mix jido_murmur.install

  Creates migrations for:
    - `jido_murmur_workspaces`
    - `jido_murmur_agent_sessions`
    - `jido_murmur_checkpoints`
    - `jido_murmur_thread_entries`

  Existing migrations are detected by module name and skipped.
  """

  use Mix.Task

  import Mix.Generator

  @migrations [
    {1, "create_jido_murmur_workspaces"},
    {2, "create_jido_murmur_agent_sessions"},
    {3, "create_jido_murmur_checkpoints"},
    {4, "create_jido_murmur_thread_entries"}
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

        content = EEx.eval_file(source, migration_module: migration_module)
        create_file(target, content)
      end
    end

    Mix.shell().info("""

    Remember to run migrations:

        $ mix ecto.migrate
    """)
  end

  defp get_migrations_path do
    path = Path.join(["priv", "repo", "migrations"])

    # Check if we're in an umbrella — use the consumer app's priv path
    if File.dir?("priv/repo/migrations") do
      "priv/repo/migrations"
    else
      path
    end
  end

  defp migration_module_prefix do
    case Mix.Project.config()[:app] do
      nil -> "MyApp.Repo.Migrations"
      app -> app |> to_string() |> Macro.camelize() |> then(&"#{&1}.Repo.Migrations")
    end
  end

  defp template_path(name) do
    Application.app_dir(:jido_murmur, "priv/templates/#{name}.exs")
  end

  defp generate_timestamp(offset) do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    # Add offset seconds to avoid timestamp collisions
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
        # Strip timestamp prefix (14 digits + underscore)
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
