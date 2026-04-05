defmodule JidoSql.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "SQL agent plugin for Jido AI 2.1 and ingress-coordinated JidoMurmur runtimes"

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
      description: @description,
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
      {:jido, "~> 2.2"},
      {:jido_ai, "~> 2.1"},
      {:jido_action, "~> 2.2"},
      {:jido_artifacts, in_umbrella: true},
      {:jido_murmur, in_umbrella: true},
      {:jason, "~> 1.0"}
    ]
  end
end
