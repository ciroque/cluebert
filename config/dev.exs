import Config

# Configure your database
config :cluebert, Cluebert.Repo,
  username: "postgres",
  password: "mysecretpassword",
  hostname: "localhost",
  database: "cluebert_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we can use it
# to bundle .js and .css sources.
config :cluebert, CluebertWeb.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  # Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
  http: [ip: {0, 0, 0, 0}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "VSe6nkzGtJFj6CuQEgX5hYlv1XpaZf6gMOI/gsyWJI74to+0aZrhijkNLvTmhEEj",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:cluebert, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:cluebert, ~w(--watch)]}
  ]

# Enable dev routes for LiveDashboard
config :cluebert, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :default_formatter, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  # Include debug annotations and locations in rendered markup.
  # Changing this configuration will require mix clean and a full recompile.
  debug_heex_annotations: true,
  debug_attributes: true,
  # Enable helpful, but potentially expensive runtime checks
  enable_expensive_runtime_checks: true
