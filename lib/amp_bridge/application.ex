defmodule AmpBridge.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AmpBridgeWeb.Telemetry,
      AmpBridge.Repo,
      {Phoenix.PubSub, name: AmpBridge.PubSub},
      # Registry for hardware controllers
      {Registry, keys: :unique, name: AmpBridge.Registry},
      # Registry for command learning sessions
      {Registry, keys: :unique, name: AmpBridge.CommandLearningRegistry},
      # USB Device Scanner - scans for USB-to-serial devices (must start before Hardware Manager)
      AmpBridge.USBDeviceScanner,
      # Hardware Manager - manages all amplifier controllers
      AmpBridge.HardwareManager,
      # Serial Decoder - handles ELAN protocol decoding
      AmpBridge.SerialDecoder,
      # Serial Manager - manages multiple serial connections
      AmpBridge.SerialManager,
      # Serial Relay - forwards data between adapters
      AmpBridge.SerialRelay,
      # Zone Manager - handles volume control and zone state tracking
      AmpBridge.ZoneManager,
      # MQTT Client - publishes zone states for Home Assistant
      AmpBridge.MQTTClient,
      AmpBridgeWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: AmpBridge.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    AmpBridgeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
