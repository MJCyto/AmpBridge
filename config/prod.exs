import Config

# Configure your database
config :amp_bridge, AmpBridge.Repo,
  database: "/app/amp_bridge_prod.db",
  pool_size: 10,
  stacktrace: false,
  show_sensitive_data_on_connection_error: false

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
