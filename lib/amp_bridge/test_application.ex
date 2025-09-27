defmodule AmpBridge.TestApplication do
  @moduledoc """
  Test Application - Uses mock processes to avoid hardware dependencies
  """
  use Application

  @impl true
  def start(_type, _args) do
    # Only start processes that are safe for testing
    children = [
      AmpBridgeWeb.Telemetry,
      AmpBridge.Repo,
      {Phoenix.PubSub, name: AmpBridge.PubSub},
      # Registry for hardware controllers
      {Registry, keys: :unique, name: AmpBridge.Registry},
      # Registry for command learning sessions
      {Registry, keys: :unique, name: AmpBridge.CommandLearningRegistry},
      # Mock hardware processes
      AmpBridge.MockUSBDeviceScanner,
      AmpBridge.MockHardwareManager,
      AmpBridge.MockSerialManager,
      # Serial Decoder - safe for testing
      AmpBridge.SerialDecoder,
      # Serial Relay - safe for testing
      AmpBridge.SerialRelay,
      # Zone Manager - safe for testing
      AmpBridge.ZoneManager,
      # MQTT Client - safe for testing (won't connect in test mode)
      AmpBridge.MQTTClient,
      # Command Queue - our new module
      AmpBridge.CommandQueue,
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
