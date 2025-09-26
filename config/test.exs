import Config

config :amp_bridge, AmpBridgeWeb.Endpoint,
  http: [
    ip: {127, 0, 0, 1},
    port: 4001
  ],
  secret_key_base: "test_secret_key_base",
  server: false

config :amp_bridge, AmpBridge.Repo,
  database: "priv/repo/amp_bridge_test.db",
  pool_size: 5

config :logger, level: :warning
config :phoenix, :plug_serve_static, false
