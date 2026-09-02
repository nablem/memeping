import Config

# Discovery pollers hit the real DEX Screener API and can't get a checked-out
# sandbox DB connection outside of a test process, so keep them off here.
config :memeping, start_recorder: false, start_updater: false, start_notifiers: false
config :memeping, dex_screener_client: MemePing.Discovery.DexScreenerTestClient

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :memeping, MemePing.Repo,
  database: Path.expand("../memeping_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :memeping, MemePingWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "65OwpeKfJV0/c2wGzY2ZTDv+v9/uai4CzV93t1BFSUDE78Id1jxV5utx0c4xWCaV",
  server: false

# In test we don't send emails
config :memeping, MemePing.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
