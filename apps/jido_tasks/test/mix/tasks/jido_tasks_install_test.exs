defmodule Mix.Tasks.JidoTasks.InstallTest do
  use ExUnit.Case

  import Igniter.Test

  describe "jido_tasks.install" do
    test "chains jido_murmur.install when jido_murmur is not configured" do
      {:ok, igniter, _} =
        test_project()
        |> Igniter.compose_task("jido_tasks.install")
        |> apply_igniter()

      content =
        igniter.rewrite
        |> Rewrite.source!("config/config.exs")
        |> Rewrite.Source.get(:content)

      # Both jido_murmur and jido_tasks config should be present
      assert content =~ "config :jido_murmur"
      assert content =~ "config :jido_tasks"
    end

    test "standalone install when jido_murmur already configured" do
      {:ok, igniter, _} =
        test_project()
        |> Igniter.compose_task("jido_murmur.install")
        |> apply_igniter!()
        |> Igniter.compose_task("jido_tasks.install")
        |> apply_igniter()

      content =
        igniter.rewrite
        |> Rewrite.source!("config/config.exs")
        |> Rewrite.Source.get(:content)

      assert content =~ "config :jido_tasks"
      assert content =~ "repo: Test.Repo"
      assert content =~ "pubsub: Test.PubSub"
    end

    test "generates create_jido_tasks migration" do
      {:ok, igniter, _} =
        test_project()
        |> Igniter.compose_task("jido_tasks.install")
        |> apply_igniter()

      sources = Map.keys(igniter.rewrite.sources)

      migration_files =
        Enum.filter(sources, fn path ->
          String.starts_with?(path, "priv/repo/migrations/") &&
            String.contains?(path, "create_jido_tasks")
        end)

      assert length(migration_files) == 1

      [file] = migration_files

      content =
        igniter.rewrite
        |> Rewrite.source!(file)
        |> Rewrite.Source.get(:content)

      assert content =~ "use Ecto.Migration"
      assert content =~ ":jido_tasks"
    end

    test "is idempotent — re-running produces no config duplicates" do
      test_project()
      |> Igniter.compose_task("jido_tasks.install")
      |> apply_igniter!()
      |> Igniter.compose_task("jido_tasks.install")
      |> assert_unchanged("config/config.exs")
    end
  end
end
