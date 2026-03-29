defmodule Mix.Tasks.JidoMurmur.InstallTest do
  use ExUnit.Case

  import Igniter.Test

  describe "jido_murmur.install" do
    test "generates all four migration files" do
      {:ok, igniter, _} =
        test_project()
        |> Igniter.compose_task("jido_murmur.install")
        |> apply_igniter()

      sources = Map.keys(igniter.rewrite.sources)

      migration_files =
        Enum.filter(sources, &String.starts_with?(&1, "priv/repo/migrations/"))

      assert length(migration_files) == 4

      migration_names =
        Enum.map(migration_files, fn f ->
          f
          |> Path.basename()
          |> String.replace(~r/^\d{14}_/, "")
          |> String.trim_trailing(".exs")
        end)

      assert "create_jido_murmur_workspaces" in migration_names
      assert "create_jido_murmur_agent_sessions" in migration_names
      assert "create_jido_murmur_checkpoints" in migration_names
      assert "create_jido_murmur_thread_entries" in migration_names
    end

    test "injects jido_murmur config into config.exs" do
      {:ok, igniter, _} =
        test_project()
        |> Igniter.compose_task("jido_murmur.install")
        |> apply_igniter()

      content =
        igniter.rewrite
        |> Rewrite.source!("config/config.exs")
        |> Rewrite.Source.get(:content)

      assert content =~ "config :jido_murmur"
      assert content =~ "repo: Test.Repo"
      assert content =~ "pubsub: Test.PubSub"
      assert content =~ "jido_mod: Test.Jido"
      assert content =~ "otp_app: :test"
    end

    test "adds supervisor to application.ex" do
      {:ok, igniter, _} =
        test_project()
        |> Igniter.compose_task("jido_murmur.install")
        |> apply_igniter()

      content =
        igniter.rewrite
        |> Rewrite.source!("lib/test/application.ex")
        |> Rewrite.Source.get(:content)

      assert content =~ "JidoMurmur.Supervisor"
    end

    test "is idempotent — re-running produces no config duplicates" do
      test_project()
      |> Igniter.compose_task("jido_murmur.install")
      |> apply_igniter!()
      |> Igniter.compose_task("jido_murmur.install")
      |> assert_unchanged("config/config.exs")
    end

    test "migration files contain valid Ecto migration code" do
      {:ok, igniter, _} =
        test_project()
        |> Igniter.compose_task("jido_murmur.install")
        |> apply_igniter()

      sources = Map.keys(igniter.rewrite.sources)

      migration_files =
        Enum.filter(sources, &String.starts_with?(&1, "priv/repo/migrations/"))

      for file <- migration_files do
        content =
          igniter.rewrite
          |> Rewrite.source!(file)
          |> Rewrite.Source.get(:content)

        assert content =~ "defmodule"
        assert content =~ "use Ecto.Migration"
        assert content =~ "def change"
      end
    end
  end
end
