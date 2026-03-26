# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :jido_ai,
  model_aliases: %{
    capable: "openai:gpt-5-mini",
    fast: "openai:gpt-5-mini"
  }

config :jido_action, default_timeout: 30000, default_max_retries: 1, default_backoff: 250
config :murmur, Murmur.Jido, max_tasks: 1000, agent_pools: []

config :murmur,
  ecto_repos: [Murmur.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :murmur, MurmurWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MurmurWeb.ErrorHTML, json: MurmurWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Murmur.PubSub,
  live_view: [signing_salt: "78A9aJAw"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  murmur: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  murmur: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Use git_hook
if Mix.env() == :dev do
  config :git_hooks,
    auto_install: true,
    verbose: true,
    hooks: [
      pre_commit: [
        tasks: [
          {:cmd, "mix format --check-formatted"},
          {:cmd, "mix credo --strict"}
        ]
      ],
      pre_push: [
        tasks: [
          {:cmd, "mix dialyzer"},
          {:cmd, "mix test"}
        ]
      ]
    ]
end

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
