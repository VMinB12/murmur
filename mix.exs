defmodule Murmur.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix, :eex]],
      aliases: aliases(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Dependencies listed here are available to all child apps.
  # Dev/test tooling that applies across the umbrella lives here.
  defp deps do
    [
      {:git_hooks, "~> 0.8", only: [:dev]},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.0", only: [:dev, :test]},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "test",
        &run_umbrella_dialyzer/1,
        "credo --strict",
        "sobelow --root apps/murmur_demo --config"
      ]
    ]
  end

  defp run_umbrella_dialyzer(_args) do
    {_output, exit_code} =
      System.cmd("mix", ["dialyzer"],
        cd: File.cwd!(),
        env: [{"MIX_ENV", "dev"}],
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    if exit_code != 0 do
      Mix.raise("mix dialyzer failed with exit code #{exit_code}")
    end
  end
end
