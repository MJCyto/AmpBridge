import Config

config :amp_bridge,
  ecto_repos: [AmpBridge.Repo]

config :amp_bridge, AmpBridgeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AmpBridgeWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: AmpBridge.PubSub,
  live_view: [signing_salt: "amp_bridge_salt"]

config :amp_bridge, AmpBridgeWeb.Gettext, locales: ~w(en)

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :phoenix, :template_engines, html: Phoenix.Template.Engine.HTML

# MQTT Configuration
config :amp_bridge, :mqtt,
  host: System.get_env("MQTT_HOST", "localhost"),
  port: String.to_integer(System.get_env("MQTT_PORT", "1885")),
  username: System.get_env("MQTT_USERNAME"),
  password: System.get_env("MQTT_PASSWORD")

import_config "#{config_env()}.exs"
