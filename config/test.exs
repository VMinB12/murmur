import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :murmur, Murmur.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "murmur_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :murmur, MurmurWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "vlHcXXv+itjrdV2bB7djTx5qptibFxdal7XJsLZhatmeaCo4mRyEO5ltddLjdMnC",
  server: false

# In test we don't send emails
config :murmur, Murmur.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Use mock LLM adapter in tests (no real API calls)
config :murmur, :llm_adapter, Murmur.Agents.LLM.Mock

# Skip hibernate (checkpoint persistence) in test — sandbox teardown causes noise
config :murmur, :skip_hibernate, true

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
