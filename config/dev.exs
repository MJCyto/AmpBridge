import Config

# Configure your database
config :amp_bridge, AmpBridge.Repo,
  database: Path.expand("../amp_bridge_dev.db", Path.dirname(__ENV__.file)),
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The http/https configuration can be controlled via
# config/runtime.exs.
config :amp_bridge, AmpBridgeWeb.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  # Change to `ip: {0, 0, 0, 0}` or `ip: {0, 0, 0, 0, 0, 0, 0, 1}` to listen on all interfaces.
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "your_secret_key_base_here_replace_in_production_with_64_byte_random_string",
  live_view: [signing_salt: "your_live_view_salt_here"]

# Enable dev routes for dashboard and mailbox
config :amp_bridge, dev_routes: true

# Configure your database
config :amp_bridge, AmpBridge.Repo,
  database: Path.expand("../amp_bridge_dev.db", Path.dirname(__ENV__.file)),
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n", level: :debug

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime
