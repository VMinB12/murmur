# Quickstart: Igniter Adoption

**Feature Branch**: `004-igniter-adoption`

## What Changed

All Murmur ecosystem packages now ship with Igniter-powered install tasks that automate setup with AST-aware code modification, diff previews, and idempotent re-runs. Igniter is optional — packages compile and function without it.

## For Package Consumers

### First-time Setup

```bash
# Add packages to your mix.exs deps, then:
mix deps.get

# Install with a single command (auto-chains prerequisites)
mix jido_tasks.install

# This will:
# 1. Detect jido_murmur isn't configured → run jido_murmur.install first
# 2. Generate all required migrations
# 3. Add config blocks to config.exs
# 4. Add supervisor to application.ex
# 5. Show a diff preview → accept or reject
```

### Scaffold a New Agent Profile

```bash
mix jido_murmur.gen.profile MyAssistant
# Creates: lib/my_app/agents/profiles/my_assistant.ex
```

### Without Igniter

If you don't want Igniter, you'll receive a clear message with manual setup instructions when running any install task.

## For Package Maintainers

### Adding Igniter to a Package

1. Add to mix.exs: `{:igniter, "~> 0.7", optional: true, runtime: false}`
2. Create install task with guard pattern:

```elixir
# lib/mix/tasks/my_package.install.ex
if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.MyPackage.Install do
    use Igniter

    def igniter(igniter) do
      igniter
      |> Igniter.Project.Config.configure(
        "config.exs",
        :my_package,
        [:pubsub],
        {:code, Sourceror.parse_string!("MyApp.PubSub")}
      )
    end
  end
else
  defmodule Mix.Tasks.MyPackage.Install do
    use Mix.Task
    def run(_args) do
      Mix.shell().error("Igniter required. Add {:igniter, \"~> 0.7\"} to deps.")
    end
  end
end
```
