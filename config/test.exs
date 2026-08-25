import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Print only warnings and errors during test
config :logger, level: :warning

# Oban runs jobs inline / disabled in tests.
config :ordo, Oban, testing: :manual

# In test we don't send emails
config :ordo, Ordo.Mailer, adapter: Swoosh.Adapters.Test

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :ordo, Ordo.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ordo_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Cloak encryption key (test only).
config :ordo, Ordo.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: Base.decode64!("6D3vv+u53e2MuhigHFQbviRFg2Q7bYq55dAwBCclsdQ=")}
  ]

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ordo, OrdoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "7cuVYD/Cf9+s0C7bWMWSBnt94VQpR0ofSELqLLgFBmmRWSo3yri8vMMWu7/TB8L+",
  server: false

# Use the fake mail fetcher in tests (no live IMAP).
config :ordo, :mailbox_fetcher, Ordo.Mailboxes.Fetcher.Fake

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false
