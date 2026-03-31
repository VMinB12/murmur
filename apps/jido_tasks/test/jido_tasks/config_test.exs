defmodule JidoTasks.ConfigTest do
  # Must be async: false — this test mutates global Application env (:repo, :pubsub)
  # which would race with other tests calling JidoTasks.repo()/pubsub().
  use ExUnit.Case, async: false

  alias JidoTasks.Config

  describe "validate!/0" do
    test "passes when all required keys are present" do
      original = Application.get_all_env(:jido_tasks)

      try do
        Application.put_env(:jido_tasks, :repo, SomeRepo)
        Application.put_env(:jido_tasks, :pubsub, SomePubSub)

        assert Config.validate!() == :ok
      after
        restore_env(:jido_tasks, original)
      end
    end

    test "raises listing missing :repo key" do
      original = Application.get_all_env(:jido_tasks)

      try do
        Application.delete_env(:jido_tasks, :repo)
        Application.put_env(:jido_tasks, :pubsub, SomePubSub)

        assert_raise RuntimeError, ~r/:repo/, fn ->
          Config.validate!()
        end
      after
        restore_env(:jido_tasks, original)
      end
    end

    test "raises listing missing :repo and :pubsub keys" do
      original = Application.get_all_env(:jido_tasks)

      try do
        Application.delete_env(:jido_tasks, :repo)
        Application.delete_env(:jido_tasks, :pubsub)

        error =
          assert_raise RuntimeError, fn ->
            Config.validate!()
          end

        assert error.message =~ ":repo"
        assert error.message =~ ":pubsub"
        assert error.message =~ "config :jido_tasks"
      after
        restore_env(:jido_tasks, original)
      end
    end
  end

  defp restore_env(app, original) do
    for {key, _} <- Application.get_all_env(app) do
      Application.delete_env(app, key)
    end

    for {key, value} <- original do
      Application.put_env(app, key, value)
    end
  end
end
