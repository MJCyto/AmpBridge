defmodule AmpBridge.MQTTClient do
  @moduledoc """
  MQTT client for publishing zone states to Home Assistant.
  """

  use GenServer
  require Logger

  alias AmpBridge.Devices

  @client_id "ampbridge_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Publish zone state to MQTT
  """
  def publish_zone_state(zone_id, state) do
    GenServer.cast(__MODULE__, {:publish_zone_state, zone_id, state})
  end

  @doc """
  Publish all zones state
  """
  def publish_all_zones do
    GenServer.cast(__MODULE__, :publish_all_zones)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    mqtt_config = Application.get_env(:amp_bridge, :mqtt, [])
    mqtt_host = Keyword.get(opts, :host) || Keyword.get(mqtt_config, :host, "localhost")
    mqtt_port = Keyword.get(opts, :port) || Keyword.get(mqtt_config, :port, 1885)
    mqtt_username = Keyword.get(opts, :username) || Keyword.get(mqtt_config, :username)
    mqtt_password = Keyword.get(opts, :password) || Keyword.get(mqtt_config, :password)
    base_topic = Keyword.get(opts, :base_topic) || Keyword.get(mqtt_config, :base_topic, "ampbridge/zones")
    keep_alive = Keyword.get(opts, :keep_alive) || Keyword.get(mqtt_config, :keep_alive, 60)

    Logger.info("Starting MQTT client connecting to #{mqtt_host}:#{mqtt_port}")
    connection_config = [
      client_id: @client_id,
      server: {Tortoise.Transport.Tcp, host: mqtt_host, port: mqtt_port},
      user_name: mqtt_username,
      password: mqtt_password,
      keep_alive: keep_alive,
      handler: {AmpBridge.MQTTHandler, []},
      will: %Tortoise.Package.Publish{
        topic: "#{base_topic}/status",
        payload: "offline",
        qos: 1,
        retain: true
      }
    ]

    # Store base_topic in state for later use
    state = %{base_topic: base_topic}
    case Tortoise.Connection.start_link(connection_config) do
      {:ok, pid} ->
        subscribe_to_control_topics(state.base_topic)
        publish_status(state.base_topic, "online")
        publish_all_zones()

        {:ok, Map.put(state, :connection_pid, pid) |> Map.put(:connected, true)}

      {:error, reason} ->
        Logger.error("Failed to connect to MQTT broker: #{inspect(reason)}")
        Logger.error("MQTT is required for zone control. Please ensure a broker is running on #{mqtt_host}:#{mqtt_port}")
        {:stop, {:shutdown, "MQTT connection failed"}}
    end
  end

  @impl true
  def handle_cast({:publish_zone_state, zone_id, state}, %{connected: true, base_topic: base_topic} = state_data) do
    zone_topic = "#{base_topic}/#{zone_id}"
    publish_zone_attributes(base_topic, zone_topic, zone_id, state)

    {:noreply, state_data}
  end

  @impl true
  def handle_cast({:publish_zone_state, _zone_id, _state}, %{connected: false} = state_data) do
    Logger.warning("MQTT not connected, cannot publish zone state")
    {:noreply, state_data}
  end

  @impl true
  def handle_cast(:publish_all_zones, %{connected: true, base_topic: base_topic} = state_data) do
    case load_all_zone_states() do
      {:ok, zones} ->
        Enum.each(zones, fn zone ->
          publish_zone_attributes(base_topic, "#{base_topic}/#{zone.id}", zone.id, zone)
        end)
        publish_discovery_info(base_topic, zones)

      {:error, reason} ->
        Logger.error("Failed to load zone states for MQTT: #{reason}")
    end

    {:noreply, state_data}
  end

  @impl true
  def handle_cast(:publish_all_zones, %{connected: false} = state_data) do
    Logger.warning("MQTT not connected, cannot publish all zones")
    {:noreply, state_data}
  end

  @impl true
  def handle_info({:tortoise, :connection, :status, status}, state_data) do
    Logger.info("MQTT connection status: #{status}")

    new_state = case status do
      :up -> %{state_data | connected: true}
      :down -> %{state_data | connected: false}
      _ -> state_data
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:tortoise, :connection, :disconnected}, state_data) do
    Logger.warning("MQTT disconnected")
    {:noreply, %{state_data | connected: false}}
  end

  @impl true
  def handle_info({:tortoise, :connection, :connected}, %{base_topic: base_topic} = state_data) do
    Logger.info("MQTT connected")
    subscribe_to_control_topics(base_topic)
    publish_status(base_topic, "online")
    {:noreply, %{state_data | connected: true}}
  end

  @impl true
  def handle_info({:tortoise, :subscription, :status, status}, state_data) do
    Logger.debug("MQTT subscription status: #{status}")
    {:noreply, state_data}
  end

  @impl true
  def handle_info({:tortoise, :subscription, :message, message}, state_data) do
    handle_mqtt_message(message)
    {:noreply, state_data}
  end

  @impl true
  def handle_info({{Tortoise, _client_id}, _ref, :ok}, state_data) do
    {:noreply, state_data}
  end

  def handle_info({{Tortoise, _client_id}, _ref, {:ok, _result}}, state_data) do
    {:noreply, state_data}
  end

  def handle_info({{Tortoise, _client_id}, _ref, {:error, reason}}, state_data) do
    Logger.error("MQTT operation failed: #{inspect(reason)}")
    {:noreply, state_data}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, state_data) do
    Logger.warning("MQTT connection lost: #{inspect(reason)}")
    {:noreply, %{state_data | connected: false}}
  end

  def handle_info(msg, state_data) do
    Logger.debug("Received unexpected message: #{inspect(msg)}")
    {:noreply, state_data}
  end

  # Private functions

  defp get_active_device_id do
    device_config = Application.get_env(:amp_bridge, :device, [])
    Keyword.get(device_config, :default_device_id, 1)
  end

  defp get_zone_range do
    case get_device() do
      nil -> 0..7  # Fallback if no device configured
      device ->
        case device.zones do
          nil -> 0..7
          zones_map when is_map(zones_map) ->
            zone_numbers = zones_map
            |> Map.keys()
            |> Enum.map(&String.to_integer/1)
            |> Enum.filter(fn zone -> zone >= 0 end)
            |> Enum.sort()

            if length(zone_numbers) > 0 do
              min_zone = List.first(zone_numbers)
              max_zone = List.last(zone_numbers)
              min_zone..max_zone
            else
              0..7
            end
          _ -> 0..7
        end
    end
  end

  defp get_device do
    device_id = get_active_device_id()
    Devices.get_device(device_id)
  end

  defp subscribe_to_control_topics(base_topic) do
    zone_range = get_zone_range()

    for zone_id <- zone_range do
      volume_topic = "#{base_topic}/#{zone_id}/volume/set"
      mute_topic = "#{base_topic}/#{zone_id}/mute/set"
      source_topic = "#{base_topic}/#{zone_id}/source/set"

      Tortoise.Connection.subscribe(@client_id, volume_topic, qos: 1)
      Tortoise.Connection.subscribe(@client_id, mute_topic, qos: 1)
      Tortoise.Connection.subscribe(@client_id, source_topic, qos: 1)
    end
  end

  def handle_mqtt_message(%{topic: topic, payload: payload}) do
    Logger.info("Received MQTT message on #{topic}: #{payload}")

    mqtt_config = Application.get_env(:amp_bridge, :mqtt, [])
    base_topic = Keyword.get(mqtt_config, :base_topic, "ampbridge/zones")

    case parse_topic(topic, base_topic) do
      {:zone_control, zone_id, action} ->
        handle_zone_control(zone_id, action, payload)
      _ ->
        Logger.debug("Unknown MQTT topic: #{topic}")
    end
  end

  defp parse_topic(topic, base_topic) when is_binary(topic) do
    base_topic_parts = String.split(base_topic, "/")
    topic_parts = String.split(topic, "/")

    # Check if topic matches pattern: {base_topic}/{zone_id}/{action}/set
    # e.g., "ampbridge/zones/0/volume/set" with base_topic "ampbridge/zones"
    if length(topic_parts) == length(base_topic_parts) + 3 do
      # Extract the parts after base_topic
      remaining_parts = Enum.drop(topic_parts, length(base_topic_parts))

      case remaining_parts do
        [zone_id_str, action, "set"] ->
          case Integer.parse(zone_id_str) do
            {zone_id, ""} ->
              {:zone_control, zone_id, action}
            _ ->
              :unknown
          end
        _ ->
          :unknown
      end
    else
      :unknown
    end
  end

  defp parse_topic(topic, base_topic) when is_list(topic) do
    base_topic_parts = String.split(base_topic, "/")

    # Check if topic matches pattern: {base_topic}/{zone_id}/{action}/set
    if length(topic) == length(base_topic_parts) + 3 do
      # Extract the parts after base_topic
      remaining_parts = Enum.drop(topic, length(base_topic_parts))

      case remaining_parts do
        [zone_id_str, action, "set"] ->
          case Integer.parse(zone_id_str) do
            {zone_id, ""} ->
              {:zone_control, zone_id, action}
            _ ->
              :unknown
          end
        _ ->
          :unknown
      end
    else
      :unknown
    end
  end

  defp handle_zone_control(zone_id, "volume", payload) do
    case Integer.parse(payload) do
      {volume, ""} when volume >= 0 and volume <= 100 ->
        case update_zone_volume(zone_id, volume) do
          :ok ->
            Logger.info("Zone #{zone_id} volume set to #{volume}% via MQTT")
          {:error, reason} ->
            Logger.error("Failed to set zone #{zone_id} volume: #{reason}")
        end
      _ ->
        Logger.warning("Invalid volume value: #{payload}")
    end
  end

  defp handle_zone_control(zone_id, "mute", payload) do
    case payload do
      "ON" ->
        case update_zone_mute(zone_id, true) do
          :ok -> Logger.info("Zone #{zone_id} muted via MQTT")
          {:error, reason} -> Logger.error("Failed to mute zone #{zone_id}: #{reason}")
        end
      "OFF" ->
        case update_zone_mute(zone_id, false) do
          :ok -> Logger.info("Zone #{zone_id} unmuted via MQTT")
          {:error, reason} -> Logger.error("Failed to unmute zone #{zone_id}: #{reason}")
        end
      _ -> Logger.warning("Invalid mute value: #{payload}")
    end
  end

  defp handle_zone_control(zone_id, "source", payload) do
    Logger.info("handle_zone_control called with zone_id: #{zone_id}, payload: '#{payload}'")

    # Map source name to "Source X" format (exactly like dashboard expects)
    mapped_source = case payload do
      "Off" -> "Off"
      source when is_binary(source) ->
        # Check if it's already in "Source X" format
        if String.match?(source, ~r/^Source \d+$/) do
          source
        else
          # Look up custom source name in configured sources map
          map_custom_source_to_source_x(source)
        end
    end

    Logger.info("Mapped source '#{payload}' -> '#{mapped_source}'")

    # Update database
    case update_zone_source_mqtt(zone_id, mapped_source) do
      :ok -> Logger.info("Zone #{zone_id} source set to #{mapped_source} via MQTT")
      {:error, reason} -> Logger.error("Failed to set zone #{zone_id} source: #{reason}")
    end
  end

  defp publish_zone_attributes(_base_topic, zone_topic, _zone_id, zone) do
    Tortoise.publish(@client_id, "#{zone_topic}/volume", to_string(zone.volume), qos: 1, retain: true)
    mute_status = if zone.muted, do: "ON", else: "OFF"
    Tortoise.publish(@client_id, "#{zone_topic}/mute", mute_status, qos: 1, retain: true)
    Tortoise.publish(@client_id, "#{zone_topic}/source", zone.source, qos: 1, retain: true)
    connection_status = if zone.connected, do: "ON", else: "OFF"
    Tortoise.publish(@client_id, "#{zone_topic}/connected", connection_status, qos: 1, retain: true)
    Tortoise.publish(@client_id, "#{zone_topic}/name", zone.name, qos: 1, retain: true)
  end

  defp publish_status(base_topic, status) do
    Tortoise.publish(@client_id, "#{base_topic}/status", status, qos: 1, retain: true)
  end

  defp publish_discovery_info(base_topic, zones) do
    Enum.each(zones, fn zone ->
      publish_zone_discovery(base_topic, zone)
    end)
  end

  defp publish_zone_discovery(base_topic, zone) do
    mqtt_config = Application.get_env(:amp_bridge, :mqtt, [])
    manufacturer = Keyword.get(mqtt_config, :manufacturer, "AmpBridge")
    model = Keyword.get(mqtt_config, :model, "Zone Controller")

    zone_id = zone.id
    zone_name = zone.name
    volume_config = %{
      "name" => "#{zone_name} Volume",
      "state_topic" => "#{base_topic}/#{zone_id}/volume",
      "unit_of_measurement" => "%",
      "device_class" => "volume_level",
      "unique_id" => "ampbridge_zone_#{zone_id}_volume",
      "device" => %{
        "identifiers" => ["ampbridge_zone_#{zone_id}"],
        "name" => zone_name,
        "manufacturer" => manufacturer,
        "model" => model
      }
    }

    Tortoise.publish(@client_id, "homeassistant/sensor/ampbridge_zone_#{zone_id}_volume/config",
                    Jason.encode!(volume_config), qos: 1, retain: true)
    mute_config = %{
      "name" => "#{zone_name} Mute",
      "state_topic" => "#{base_topic}/#{zone_id}/mute",
      "command_topic" => "#{base_topic}/#{zone_id}/mute/set",
      "payload_on" => "ON",
      "payload_off" => "OFF",
      "unique_id" => "ampbridge_zone_#{zone_id}_mute",
      "device" => %{
        "identifiers" => ["ampbridge_zone_#{zone_id}"],
        "name" => zone_name,
        "manufacturer" => manufacturer,
        "model" => model
      }
    }

    Tortoise.publish(@client_id, "homeassistant/switch/ampbridge_zone_#{zone_id}_mute/config",
                    Jason.encode!(mute_config), qos: 1, retain: true)
  end

  defp load_all_zone_states do
    try do
      device = get_device()

      if device && device.zones && map_size(device.zones) > 0 do
        zones_map = device.zones
        mute_states = device.mute_states || %{}
        source_states = device.source_states || %{}
        volume_states = device.volume_states || %{}
        sources_map = device.sources || %{}

        zone_numbers =
          zones_map
          |> Map.keys()
          |> Enum.map(&String.to_integer/1)
          |> Enum.filter(fn zone -> zone >= 0 end)
          |> Enum.sort()

        # Create source mapping from configured sources
        # Use configured sources if available, otherwise empty map
        source_mapping = create_source_mapping(sources_map)

        zones =
          zone_numbers
          |> Enum.map(fn zone ->
            zone_name = get_zone_name(zones_map, zone)
            current_mute = Map.get(mute_states, to_string(zone), false)
            raw_source = Map.get(source_states, to_string(zone), nil)
            current_source = map_source_name(raw_source, source_mapping)
            current_volume = Map.get(volume_states, to_string(zone), 50)

            %{
              id: zone,  # Use 0-based indexing for MQTT
              name: zone_name || "Zone #{zone + 1}",
              volume: current_volume,
              muted: current_mute,
              source: current_source || "Off",
              connected: check_adapters_connected()
            }
          end)

        {:ok, zones}
      else
        # No device or zones configured - return empty list
        Logger.warning("No device or zones configured, returning empty zone list")
        {:ok, []}
      end
    rescue
      error ->
        Logger.error("Failed to load zone states: #{inspect(error)}")
        {:error, "Database error"}
    end
  end

  defp get_zone_name(zones_map, zone_id) do
    case Map.get(zones_map, to_string(zone_id)) do
      %{"name" => name} when is_binary(name) and name != "" -> name
      _ -> nil
    end
  end

  defp create_source_mapping(sources_map) do
    if sources_map && map_size(sources_map) > 0 do
      sources_map
      |> Map.keys()
      |> Enum.sort()
      |> Enum.with_index()
      |> Enum.map(fn {key, index} ->
        source_data = Map.get(sources_map, key)
        source_name = Map.get(source_data, "name", "Source #{index + 1}")
        {"Source #{index + 1}", source_name}
      end)
      |> Enum.into(%{})
    else
      %{}
    end
  end

  defp map_source_name(raw_source, source_mapping) do
    case raw_source do
      nil -> nil
      "Off" -> nil
      source when is_binary(source) ->
        Map.get(source_mapping, source, source)
      _ -> nil
    end
  end

  defp map_custom_source_to_source_x(custom_source_name) do
    try do
      device = get_device()

      if device do
        sources_map = device.sources || %{}

        if map_size(sources_map) > 0 do
          # Search through sources map to find matching custom name
          sources_map
          |> Map.keys()
          |> Enum.sort()
          |> Enum.with_index()
          |> Enum.find_value(fn {key, index} ->
            source_data = Map.get(sources_map, key)
            source_name = Map.get(source_data, "name", "Source #{index + 1}")
            if source_name == custom_source_name do
              "Source #{index + 1}"
            else
              nil
            end
          end)
          |> case do
            nil ->
              Logger.warning("Could not map custom source name '#{custom_source_name}' to 'Source X' format")
              custom_source_name  # Return original if not found
            mapped -> mapped
          end
        else
          Logger.warning("No sources configured, cannot map custom source name '#{custom_source_name}'")
          custom_source_name  # Return original if no sources configured
        end
      else
        Logger.warning("No device configured, cannot map custom source name '#{custom_source_name}'")
        custom_source_name  # Return original if no device
      end
    rescue
      error ->
        Logger.error("Failed to map custom source name '#{custom_source_name}': #{inspect(error)}")
        custom_source_name  # Return original on error
    end
  end

  defp check_adapters_connected do
    try do
      connection_status = AmpBridge.SerialManager.get_connection_status()
      connection_status.adapter_1.connected && connection_status.adapter_2.connected
    rescue
      _ -> false
    end
  end

  defp update_zone_volume(zone_id, volume) do
    try do
      device_id = get_active_device_id()
      device = AmpBridge.Devices.get_device!(device_id)
      current_volume_states = device.volume_states || %{}
      updated_volume_states = Map.put(current_volume_states, to_string(zone_id), volume)

      case AmpBridge.Devices.update_device(device, %{volume_states: updated_volume_states}) do
        {:ok, _updated_device} ->
          send_volume_command(zone_id, volume)

          current_mute_states = device.mute_states || %{}
          current_mute_state = Map.get(current_mute_states, to_string(zone_id), false)

          if current_mute_state do
            Logger.info("Zone #{zone_id} was muted, unmuting due to volume change")
            update_zone_mute(zone_id, false)
          end

          Phoenix.PubSub.broadcast(
            AmpBridge.PubSub,
            "device_updates",
            {:zone_volume_changed, zone_id, volume}
          )
          publish_zone_update(zone_id)

          :ok

        {:error, changeset} ->
          Logger.error("Failed to update zone #{zone_id} volume: #{inspect(changeset)}")
          {:error, "Database update failed"}
      end
    rescue
      error ->
        Logger.error("Failed to update zone volume: #{inspect(error)}")
        {:error, "Database error"}
    end
  end

  defp send_volume_command(zone_id, volume) do
    try do
      zone_manager_zone = zone_id + 1

      case AmpBridge.HexCommandManager.get_volume_command(zone_manager_zone, volume) do
        {:ok, hex_chunks} ->
          send_hex_chunks(:adapter_1, hex_chunks, "volume")
          Logger.info("Sent volume command for zone #{zone_id} to #{volume}%")

        {:error, reason} ->
          Logger.error("Failed to get volume command for zone #{zone_id}: #{reason}")
      end
    rescue
      error ->
        Logger.error("Failed to send volume command: #{inspect(error)}")
    end
  end

  defp send_hex_chunks(adapter, hex_chunks, command_type) do
    Enum.each(hex_chunks, fn chunk ->
      case AmpBridge.SerialManager.send_command(adapter, chunk) do
        :ok ->
          Logger.debug("Sent #{command_type} chunk: #{inspect(chunk)}")
        {:error, reason} ->
          Logger.error("Failed to send #{command_type} chunk: #{reason}")
      end
    end)
  end

  defp update_zone_mute(zone_id, muted) do
    try do
      device_id = get_active_device_id()
      device = AmpBridge.Devices.get_device!(device_id)
      current_mute_states = device.mute_states || %{}
      updated_mute_states = Map.put(current_mute_states, to_string(zone_id), muted)

      case AmpBridge.Devices.update_device(device, %{mute_states: updated_mute_states}) do
        {:ok, _updated_device} ->
          send_mute_command(zone_id, muted)

          Phoenix.PubSub.broadcast(
            AmpBridge.PubSub,
            "device_updates",
            {:zone_mute_changed, zone_id, muted}
          )
          publish_zone_update(zone_id)

          :ok

        {:error, changeset} ->
          Logger.error("Failed to update zone #{zone_id} mute: #{inspect(changeset)}")
          {:error, "Database update failed"}
      end
    rescue
      error ->
        Logger.error("Failed to update zone mute: #{inspect(error)}")
        {:error, "Database error"}
    end
  end

  defp send_mute_command(zone_id, muted) do
    try do
      if muted do
        case AmpBridge.HexCommandManager.get_mute_command(zone_id) do
          {:ok, hex_chunks} ->
            send_hex_chunks(:adapter_1, hex_chunks, "mute")
            Logger.info("Sent mute command for zone #{zone_id}")

          {:error, reason} ->
            Logger.error("Failed to get mute command for zone #{zone_id}: #{reason}")
        end
      else
        case AmpBridge.HexCommandManager.get_unmute_command(zone_id) do
          {:ok, hex_chunks} ->
            send_hex_chunks(:adapter_1, hex_chunks, "unmute")
            Logger.info("Sent unmute command for zone #{zone_id}")

          {:error, reason} ->
            Logger.error("Failed to get unmute command for zone #{zone_id}: #{reason}")
        end
      end
    rescue
      error ->
        Logger.error("Failed to send mute command: #{inspect(error)}")
    end
  end

  defp update_zone_source_mqtt(zone_id, source) do
    try do
      device_id = get_active_device_id()
      device = AmpBridge.Devices.get_device!(device_id)

      # Convert "Off" to nil for database storage
      stored_source = case source do
        "Off" -> nil
        source -> source
      end

      current_source_states = device.source_states || %{}
      updated_source_states = Map.put(current_source_states, to_string(zone_id), stored_source)

      case AmpBridge.Devices.update_device(device, %{source_states: updated_source_states}) do
        {:ok, _updated_device} ->
          # Send the serial command (source is already in correct format)
          send_source_command(zone_id, source)

          # Broadcast the change to the dashboard
          # Convert nil to "Off" for display consistency
          display_source = source || "Off"
          Phoenix.PubSub.broadcast(
            AmpBridge.PubSub,
            "device_updates",
            {:zone_source_changed, zone_id, display_source}
          )

          publish_zone_update(zone_id)
          :ok

        {:error, changeset} ->
          Logger.error("Failed to update zone #{zone_id} source: #{inspect(changeset)}")
          {:error, "Database update failed"}
      end
    rescue
      error ->
        Logger.error("Failed to update zone source: #{inspect(error)}")
        {:error, "Database error"}
    end
  end

  defp send_source_command(zone_id, source) do
    Logger.info("Zone #{zone_id} source changed to #{source}")

    # Get the device ID from the first device
    case Devices.list_devices() do
      [device | _] ->
        device_id = device.id

        # Parse source name to get source index or handle "Off"
        case source do
          "Off" ->
            # Send turn_off command using CommandLearner (exactly like dashboard)
            Logger.info("Sending turn_off command for zone #{zone_id} using device #{device_id}")
            case AmpBridge.CommandLearner.execute_command(device_id, "turn_off", zone_id) do
              {:ok, :command_sent} ->
                Logger.info("Turn off command sent successfully for zone #{zone_id}")
              {:error, reason} ->
                Logger.warning("Failed to send turn off command for zone #{zone_id}: #{reason}")
            end
          source_name when is_binary(source_name) ->
            # Extract index from "Source X" format (1-based to 0-based) - exactly like dashboard
            case Regex.run(~r/Source (\d+)/, source_name) do
              [_, index_str] ->
                source_index = String.to_integer(index_str) - 1
                Logger.info("Sending change_source command for zone #{zone_id}, source_index #{source_index} using device #{device_id}")

                # Use CommandLearner to execute learned change_source commands (exactly like dashboard)
                case AmpBridge.CommandLearner.execute_command(device_id, "change_source", zone_id, source_index: source_index) do
                  {:ok, :command_sent} ->
                    Logger.info("Change source command sent successfully for zone #{zone_id}, source #{source_index}")
                  {:error, reason} ->
                    Logger.warning("Failed to send change source command for zone #{zone_id}, source #{source_index}: #{reason}")
                    # Fallback to ZoneManager if learned command fails (exactly like dashboard)
                    Logger.info("Falling back to ZoneManager for source change")
                    zone_manager_zone = zone_id + 1
                    AmpBridge.ZoneManager.change_zone_source(zone_manager_zone, source_index)
                end
              nil ->
                Logger.warning("Could not parse source name: #{source_name}")
            end
        end
      [] ->
        Logger.warning("No devices found, cannot execute source command")
    end
  end

  def publish_zone_update(zone_id) do
    Logger.info("publish_zone_update called for zone #{zone_id}")
    mqtt_config = Application.get_env(:amp_bridge, :mqtt, [])
    base_topic = Keyword.get(mqtt_config, :base_topic, "ampbridge/zones")

    case load_zone_state(zone_id) do
      {:ok, zone} ->
        Logger.info("Loaded zone state for zone #{zone_id}: #{inspect(zone)}")
        zone_topic = "#{base_topic}/#{zone_id}"
        publish_zone_attributes(base_topic, zone_topic, zone_id, zone)
        Logger.info("Published updated state for zone #{zone_id}")
      {:error, reason} ->
        Logger.error("Failed to load zone #{zone_id} state for MQTT update: #{reason}")
    end
  end

  defp load_zone_state(zone_id) do
    try do
      device = get_device()

      if device do
        volume_states = device.volume_states || %{}
        mute_states = device.mute_states || %{}
        source_states = device.source_states || %{}
        sources_map = device.sources || %{}
        zones_map = device.zones || %{}

        volume = Map.get(volume_states, to_string(zone_id), 0)
        muted = Map.get(mute_states, to_string(zone_id), false)
        raw_source = Map.get(source_states, to_string(zone_id), nil)
        zone_name = get_zone_name(zones_map, zone_id)

        # Map source name using configured sources
        source_mapping = create_source_mapping(sources_map)
        source = map_source_name(raw_source, source_mapping)

        zone = %{
          id: zone_id,
          volume: volume,
          muted: muted,
          source: source || "Off",
          connected: true,
          name: zone_name || "Zone #{zone_id + 1}"
        }

        {:ok, zone}
      else
        {:error, "No device configured"}
      end
    rescue
      error ->
        Logger.error("Failed to load zone #{zone_id} state: #{inspect(error)}")
        {:error, "Failed to load zone state"}
    end
  end

end
