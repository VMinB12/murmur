defmodule JidoMurmur.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/agentjido/jido_murmur"

  def project do
    [
      app: :jido_murmur,
      version: @version,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [threshold: 80],
      description: "Multi-agent orchestration for Jido — Runner, Plugins, Storage, Schemas",
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
      {:jido_ai, "~> 2.0"},
      {:jido_signal, "~> 2.0"},
      {:jido_action, "~> 2.0"},
      {:req_llm, "~> 1.0"},
      {:phoenix_pubsub, "~> 2.0"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:jason, "~> 1.2"},
      {:mox, "~> 1.0", only: [:dev, :test]},
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv/templates .formatter.exs mix.exs README.md LICENSE)
    ]
  end
end
