import Config

alias Ecto.Adapters.SQL.Sandbox

# jido_murmur test repo configuration (for isolated package tests)
config :jido_murmur, JidoMurmur.TestRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "murmur_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Sandbox,
  pool_size: System.schedulers_online() * 2

# jido_murmur package — use mock LLM adapter in tests
config :jido_murmur, :llm_adapter, JidoMurmur.LLM.Mock

# Skip hibernate (checkpoint persistence) in test — sandbox teardown causes noise
config :jido_murmur, :skip_hibernate, true
config :jido_murmur, observability: [enabled: true, capture_content: true]

# SQL agent target database (uses the same test database for simplicity)
config :jido_sql, JidoSql.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "murmur_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Sandbox,
  pool_size: System.schedulers_online() * 2

# jido_tasks test repo configuration (for isolated package tests)
config :jido_tasks, JidoTasks.TestRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "murmur_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Sandbox,
  pool_size: System.schedulers_online() * 2

# Print only warnings and errors during test
config :logger, level: :warning

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :murmur_demo, Murmur.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "murmur_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :murmur_demo, MurmurWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "vlHcXXv+itjrdV2bB7djTx5qptibFxdal7XJsLZhatmeaCo4mRyEO5ltddLjdMnC",
  server: false

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
