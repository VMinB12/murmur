defmodule Mix.Tasks.JidoMurmur.InstallTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.JidoMurmur.Install

  @moduletag :tmp_dir

  describe "run/1" do
    test "creates migration files in priv/repo/migrations", %{tmp_dir: tmp_dir} do
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
        assert output =~ "Remember to run migrations"

        files = File.ls!(migrations_path)
        assert length(files) == 4

        assert Enum.any?(files, &String.contains?(&1, "create_jido_murmur_workspaces"))
        assert Enum.any?(files, &String.contains?(&1, "create_jido_murmur_agent_sessions"))
        assert Enum.any?(files, &String.contains?(&1, "create_jido_murmur_checkpoints"))
        assert Enum.any?(files, &String.contains?(&1, "create_jido_murmur_thread_entries"))
      after
        File.cd!(original_dir)
      end
    end

    test "skips existing migrations", %{tmp_dir: tmp_dir} do
      migrations_path = Path.join(tmp_dir, "priv/repo/migrations")
      File.mkdir_p!(migrations_path)

      # Create a pre-existing migration
      File.write!(
        Path.join(migrations_path, "20260101000000_create_jido_murmur_workspaces.exs"),
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

        files =
          File.ls!(migrations_path)
          |> Enum.reject(&(&1 == "20260101000000_create_jido_murmur_workspaces.exs"))

        # Should only create 3 new files (workspaces was skipped)
        assert length(files) == 3
      after
        File.cd!(original_dir)
      end
    end

    test "migration files contain valid Elixir code", %{tmp_dir: tmp_dir} do
      migrations_path = Path.join(tmp_dir, "priv/repo/migrations")
      File.mkdir_p!(migrations_path)

      original_dir = File.cwd!()
      File.cd!(tmp_dir)

      try do
        capture_io(fn ->
          Install.run([])
        end)

        for file <- File.ls!(migrations_path) do
          content = File.read!(Path.join(migrations_path, file))
          assert content =~ "defmodule"
          assert content =~ "use Ecto.Migration"
        end
      after
        File.cd!(original_dir)
      end
    end
  end
end
