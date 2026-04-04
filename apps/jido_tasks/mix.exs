defmodule JidoTasks.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/agentjido/jido_tasks"

  def project do
    [
      app: :jido_tasks,
      version: @version,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [summary: [threshold: 80]],
      description: "Task management tools for Jido agents",
      package: package(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jido_murmur, jido_murmur_dep()},
      {:jido_arxiv, in_umbrella: true, only: :test},
      {:igniter, "~> 0.7", optional: true, runtime: false},
      {:jido, "~> 2.2"},
      {:jido_action, "~> 2.2"},
      {:phoenix_pubsub, "~> 2.0"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:jason, "~> 1.2"},
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end

  defp jido_murmur_dep do
    if System.get_env("HEX_PUBLISH"),
      do: "~> #{@version}",
      else: [in_umbrella: true]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv/templates .formatter.exs mix.exs README.md LICENSE)
    ]
  end
end
