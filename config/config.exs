# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  ordo: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Oban — mailbox polling. A cron job fans out one PollMailbox per active mailbox.
config :ordo, Oban,
  repo: Ordo.Repo,
  queues: [mailbox: 5],
  plugins: [
    {Oban.Plugins.Cron, crontab: [{"* * * * *", Ordo.Mailboxes.ScheduleJob}]}
  ]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :ordo, Ordo.Mailer, adapter: Swoosh.Adapters.Local

# Configure the endpoint
config :ordo, OrdoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: OrdoWeb.ErrorHTML, json: OrdoWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Ordo.PubSub,
  live_view: [signing_salt: "VkyjPexe"]

config :ordo, :scopes,
  user: [
    default: true,
    module: Ordo.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Ordo.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :ordo,
  ecto_repos: [Ordo.Repo],
  generators: [timestamp_type: :utc_datetime]

# Polish is the default language (UI copy, emails, and validation errors).
config :gettext, :default_locale, "pl"

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  ordo: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
