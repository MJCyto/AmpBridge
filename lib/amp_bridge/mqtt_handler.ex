defmodule AmpBridge.MQTTHandler do
  @moduledoc """
  Tortoise MQTT handler for processing incoming messages.
  """

  use Tortoise.Handler
  require Logger

  @impl Tortoise.Handler
  def init(opts) do
    {:ok, opts}
  end

  @impl Tortoise.Handler
  def connection(status, state) do
    Logger.info("MQTT connection status: #{status}")
    {:ok, state}
  end

  @impl Tortoise.Handler
  def terminate(reason, state) do
    Logger.info("MQTT handler terminated: #{inspect(reason)}")
    {:ok, state}
  end

  @impl Tortoise.Handler
  def handle_message(topic, payload, state) do
    Logger.info("Received MQTT message on #{topic}: #{payload}")

    # Process the message using the MQTT client's handler
    AmpBridge.MQTTClient.handle_mqtt_message(%{topic: topic, payload: payload})

    {:ok, state}
  end
end
