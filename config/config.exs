import Config

# In dev, load project-root .env into the OS environment before MQTT config below.
if Mix.env() == :dev do
  env_path = Path.expand("../.env", __DIR__)

  if File.exists?(env_path) do
    env_path
    |> File.read!()
    |> String.split("\n")
    |> Enum.each(fn line ->
      line = String.trim(line)

      if line != "" and not String.starts_with?(line, "#") do
        case String.split(line, "=", parts: 2) do
          [key, value] ->
            value =
              value
              |> String.trim()
              |> String.trim("\"")
              |> String.trim("'")

            System.put_env(String.trim(key), value)

          _ ->
            :ok
        end
      end
    end)
  end
end

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
  password: System.get_env("MQTT_PASSWORD"),
  base_topic: System.get_env("MQTT_BASE_TOPIC", "ampbridge/zones"),
  keep_alive: String.to_integer(System.get_env("MQTT_KEEP_ALIVE", "60")),
  manufacturer: System.get_env("MQTT_MANUFACTURER", "AmpBridge"),
  model: System.get_env("MQTT_MODEL", "Zone Controller")

# Device Configuration
config :amp_bridge, :device,
  default_device_id: String.to_integer(System.get_env("DEFAULT_DEVICE_ID", "1"))

# On boot: DB + MQTT show all configured zones Off + unmuted; best-effort serial turn_off between commands.
config :amp_bridge, AmpBridge.StartupZoneDefaults,
  command_gap_ms: String.to_integer(System.get_env("STARTUP_ZONE_DEFAULTS_GAP_MS", "50"))

import_config "#{config_env()}.exs"
