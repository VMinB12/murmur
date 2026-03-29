defmodule Mix.Tasks.JidoTasks.InstallTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.JidoTasks.Install

  @moduletag :tmp_dir

  describe "run/1" do
    test "creates migration file in priv/repo/migrations", %{tmp_dir: tmp_dir} do
      migrations_path = Path.join(tmp_dir, "priv/repo/migrations")
      File.mkdir_p!(migrations_path)

      original_dir = File.cwd!()
      File.cd!(tmp_dir)

      try do
        output =
          capture_io(fn ->
            Install.run([])
          end)

        assert output =~ "creating"
        assert output =~ "Ensure jido_murmur migrations are run first"

        files = File.ls!(migrations_path)
        assert length(files) == 1
        assert Enum.any?(files, &String.contains?(&1, "create_jido_tasks"))
      after
        File.cd!(original_dir)
      end
    end

    test "skips existing migration", %{tmp_dir: tmp_dir} do
      migrations_path = Path.join(tmp_dir, "priv/repo/migrations")
      File.mkdir_p!(migrations_path)

      File.write!(
        Path.join(migrations_path, "20260101000000_create_jido_tasks.exs"),
        "# existing"
      )

      original_dir = File.cwd!()
      File.cd!(tmp_dir)

      try do
        output =
          capture_io(fn ->
            Install.run([])
          end)

        assert output =~ "already exists, skipping"
      after
        File.cd!(original_dir)
      end
    end

    test "migration file contains valid Elixir code", %{tmp_dir: tmp_dir} do
      migrations_path = Path.join(tmp_dir, "priv/repo/migrations")
      File.mkdir_p!(migrations_path)

      original_dir = File.cwd!()
      File.cd!(tmp_dir)

      try do
        capture_io(fn ->
          Install.run([])
        end)

        [file] = File.ls!(migrations_path)
        content = File.read!(Path.join(migrations_path, file))

        assert content =~ "defmodule"
        assert content =~ "use Ecto.Migration"
        assert content =~ "jido_tasks"
      after
        File.cd!(original_dir)
      end
    end
  end
end
