defmodule JidoMurmur.ConfigTest do
  # Cannot be async — tests mutate global Application env which races with
  # other async tests that read :jido_murmur config (e.g. EctoTest).
  use ExUnit.Case, async: false

  alias JidoMurmur.Config

  describe "validate!/0" do
    test "passes when all required keys are present" do
      original = Application.get_all_env(:jido_murmur)

      try do
        Application.put_env(:jido_murmur, :repo, SomeRepo)
        Application.put_env(:jido_murmur, :pubsub, SomePubSub)
        Application.put_env(:jido_murmur, :jido_mod, SomeJido)
        Application.put_env(:jido_murmur, :otp_app, :some_app)

        assert Config.validate!() == :ok
      after
        restore_env(:jido_murmur, original)
      end
    end

    test "raises with clear message listing missing :repo key" do
      original = Application.get_all_env(:jido_murmur)

      try do
        Application.delete_env(:jido_murmur, :repo)
        Application.put_env(:jido_murmur, :pubsub, SomePubSub)
        Application.put_env(:jido_murmur, :jido_mod, SomeJido)
        Application.put_env(:jido_murmur, :otp_app, :some_app)

        assert_raise RuntimeError, ~r/:repo/, fn ->
          Config.validate!()
        end
      after
        restore_env(:jido_murmur, original)
      end
    end

    test "raises with multiple missing keys" do
      original = Application.get_all_env(:jido_murmur)

      try do
        Application.delete_env(:jido_murmur, :repo)
        Application.delete_env(:jido_murmur, :pubsub)
        Application.delete_env(:jido_murmur, :jido_mod)
        Application.delete_env(:jido_murmur, :otp_app)

        error =
          assert_raise RuntimeError, fn ->
            Config.validate!()
          end

        assert error.message =~ ":repo"
        assert error.message =~ ":pubsub"
        assert error.message =~ ":jido_mod"
        assert error.message =~ ":otp_app"
        assert error.message =~ "config :jido_murmur"
      after
        restore_env(:jido_murmur, original)
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
