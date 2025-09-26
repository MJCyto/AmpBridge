import Config

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :amp_bridge, AmpBridgeWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    live_view: [signing_salt: "your_live_view_salt_here"],
    server: true,
    check_origin: false

  config :amp_bridge, AmpBridge.Repo,
    database: System.get_env("DATABASE_PATH") || "priv/repo/amp_bridge_prod.db",
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
end
