defmodule JidoArtifacts.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/agentjido/jido_artifacts"

  def project do
    [
      app: :jido_artifacts,
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
      description: "Artifact system for Jido agents — emit, merge, store, and broadcast artifacts",
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
      {:jido, "~> 2.0"},
      {:jido_signal, "~> 2.0"},
      {:jido_action, "~> 2.0"},
      {:phoenix_pubsub, "~> 2.0"},
      {:jason, "~> 1.0"}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end
end
