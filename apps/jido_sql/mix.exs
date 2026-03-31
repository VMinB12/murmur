defmodule JidoSql.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :jido_sql,
      version: @version,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {JidoSql.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto_sql, "~> 3.0"},
      {:postgrex, ">= 0.0.0"},
      {:jido, "~> 2.0"},
      {:jido_ai, "~> 2.0"},
      {:jido_action, "~> 2.0"},
      {:jido_artifacts, in_umbrella: true},
      {:jido_murmur, in_umbrella: true},
      {:jason, "~> 1.0"}
    ]
  end
end
