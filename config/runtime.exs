import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/cluebert start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :cluebert, CluebertWeb.Endpoint, server: true
end

config :cluebert, CluebertWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :cluebert, CluebertWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
        # Gettext translations
        ~r"priv/gettext/.*\.po$",
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/cluebert_web/router\.ex$",
        ~r"lib/cluebert_web/(controllers|live|components)/.*\.(ex|heex)$"
      ]
    ]
end

if config_env() == :prod do
  # Either DATABASE_URL, or its parts in separate variables (as the Helm
  # chart sets them), so a password needs no URL escaping.
  database =
    case System.get_env("DATABASE_URL") do
      nil ->
        fetch = fn name ->
          System.get_env(name) ||
            raise """
            environment variable #{name} is missing.
            Set DATABASE_URL (ecto://USER:PASS@HOST/DATABASE), or DATABASE_HOST,
            DATABASE_NAME, DATABASE_USERNAME and DATABASE_PASSWORD.
            """
        end

        [
          hostname: fetch.("DATABASE_HOST"),
          port: String.to_integer(System.get_env("DATABASE_PORT", "5432")),
          database: fetch.("DATABASE_NAME"),
          username: fetch.("DATABASE_USERNAME"),
          password: fetch.("DATABASE_PASSWORD")
        ]

      url ->
        [url: url]
    end

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :cluebert, Cluebert.Repo, database

  config :cluebert, Cluebert.Repo,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :cluebert, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :cluebert, CluebertWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base
end
