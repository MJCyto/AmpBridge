defmodule AmpBridgeWeb.ZoneController do
  use Phoenix.Controller, formats: [:json]
  require Logger

  alias AmpBridge.Devices
  alias AmpBridge.HexCommandManager
  alias AmpBridge.SerialManager

  @doc """
  Health check endpoint to verify all services are ready
  """
  def health(conn, _params) do
    # Check if all critical services are running
    services_status = %{
      database: check_database(),
      mqtt: check_mqtt(),
      serial_manager: check_serial_manager(),
      usb_scanner: check_usb_scanner(),
      hardware_manager: check_hardware_manager()
    }

    all_ready = Enum.all?(services_status, fn {_service, status} -> status == :ready end)

    status_code = if all_ready, do: 200, else: 503

    conn
    |> put_status(status_code)
    |> json(%{
      status: if(all_ready, do: "healthy", else: "unhealthy"),
      services: services_status,
      timestamp: DateTime.utc_now()
    })
  end

  @doc """
  Get all zones with their current states
  """
  def index(conn, _params) do
    case load_zone_states() do
      {:ok, zones} ->
        json(conn, %{
          success: true,
          zones: zones,
          timestamp: DateTime.utc_now()
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          success: false,
          error: "Failed to load zones: #{reason}",
          timestamp: DateTime.utc_now()
        })
    end
  end

  @doc """
  Get a specific zone by ID
  """
  def show(conn, %{"id" => zone_id}) do
    zone_num = String.to_integer(zone_id)

    case load_zone_state(zone_num) do
      {:ok, zone} ->
        json(conn, %{
          success: true,
          zone: zone,
          timestamp: DateTime.utc_now()
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          success: false,
          error: "Zone #{zone_id} not found",
          timestamp: DateTime.utc_now()
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          success: false,
          error: "Failed to load zone: #{reason}",
          timestamp: DateTime.utc_now()
        })
    end
  end

  @doc """
  Set zone volume
  """
  def set_volume(conn, %{"id" => zone_id, "volume" => volume}) do
    zone_num = String.to_integer(zone_id)
    volume_num = String.to_integer(volume)

    if volume_num < 0 or volume_num > 100 do
      conn
      |> put_status(:bad_request)
      |> json(%{
        success: false,
        error: "Volume must be between 0 and 100",
        timestamp: DateTime.utc_now()
      })
    else
      case update_zone_volume(zone_num, volume_num) do
        :ok ->
          json(conn, %{
            success: true,
            message: "Zone #{zone_id} volume set to #{volume_num}%",
            timestamp: DateTime.utc_now()
          })

        {:error, reason} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{
            success: false,
            error: "Failed to set volume: #{reason}",
            timestamp: DateTime.utc_now()
          })
      end
    end
  end

  @doc """
  Toggle zone mute
  """
  def toggle_mute(conn, %{"id" => zone_id}) do
    zone_num = String.to_integer(zone_id)

    case get_current_mute_state(zone_num) do
      {:ok, current_mute} ->
        new_mute = !current_mute

        case update_zone_mute(zone_num, new_mute) do
          :ok ->
            json(conn, %{
              success: true,
              message: "Zone #{zone_id} #{if new_mute, do: "muted", else: "unmuted"}",
              muted: new_mute,
              timestamp: DateTime.utc_now()
            })

          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{
              success: false,
              error: "Failed to toggle mute: #{reason}",
              timestamp: DateTime.utc_now()
            })
        end

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          success: false,
          error: "Failed to get current mute state: #{reason}",
          timestamp: DateTime.utc_now()
        })
    end
  end

  @doc """
  Set zone source
  """
  def set_source(conn, %{"id" => zone_id, "source" => source}) do
    zone_num = String.to_integer(zone_id)

    case update_zone_source(zone_num, source) do
      :ok ->
        json(conn, %{
          success: true,
          message: "Zone #{zone_id} source set to #{source}",
          timestamp: DateTime.utc_now()
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          success: false,
          error: "Failed to set source: #{reason}",
          timestamp: DateTime.utc_now()
        })
    end
  end

  # Private helper functions

  defp load_zone_states do
    try do
      device = Devices.get_device(1)

      if device && device.zones && map_size(device.zones) > 0 do
        zones_map = device.zones
        sources_map = device.sources || %{}

        # Extract zone numbers and convert to 0-based indexing
        zone_numbers =
          zones_map
          |> Map.keys()
          |> Enum.map(&String.to_integer/1)
          |> Enum.map(fn zone -> zone - 1 end)
          |> Enum.filter(fn zone -> zone >= 0 end)
          |> Enum.sort()

        # Load states from database
        mute_states = device.mute_states || %{}
        source_states = device.source_states || %{}
        volume_states = device.volume_states || %{}

        # Create zone sources list
        sources_list =
          sources_map
          |> Map.keys()
          |> Enum.sort()
          |> Enum.map(fn key ->
            source_data = Map.get(sources_map, key)
            Map.get(source_data, "name", "Source #{String.to_integer(key) + 1}")
          end)

        # Create source mapping from configured sources
        source_mapping = create_source_mapping(sources_map)

        # Build zones data
        zones =
          zone_numbers
          |> Enum.map(fn zone ->
            zone_name = get_zone_name(zones_map, zone)
            current_mute = Map.get(mute_states, to_string(zone), false)
            raw_source = Map.get(source_states, to_string(zone), nil)
            current_source = map_source_name(raw_source, source_mapping)
            current_volume = Map.get(volume_states, to_string(zone), 50)

            %{
              id: zone,
              name: zone_name || "Zone #{zone + 1}",
              volume: current_volume,
              muted: current_mute,
              source: current_source || "Off",
              available_sources: sources_list,
              connected: check_adapters_connected()
            }
          end)

        {:ok, zones}
      else
        # Fallback to default zones if no configuration
        default_zones = [0, 1, 2, 3, 4, 5, 6, 7]

        zones =
          default_zones
          |> Enum.map(fn zone ->
            %{
              id: zone,
              name: "Zone #{zone + 1}",
              volume: 50,
              muted: false,
              source: "Off",
              available_sources: ["Source 1", "Source 2"],
              connected: check_adapters_connected()
            }
          end)

        {:ok, zones}
      end
    rescue
      error ->
        Logger.error("Failed to load zone states: #{inspect(error)}")
        {:error, "Database error"}
    end
  end

  defp load_zone_state(zone_num) do
    case load_zone_states() do
      {:ok, zones} ->
        case Enum.find(zones, &(&1.id == zone_num)) do
          nil -> {:error, :not_found}
          zone -> {:ok, zone}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_zone_name(zones_map, zone) do
    # Get the configured zone numbers and sort them
    configured_zones = zones_map
    |> Map.keys()
    |> Enum.map(&String.to_integer/1)
    |> Enum.sort()

    # Map 0-based zone index to the corresponding configured zone number
    case Enum.at(configured_zones, zone) do
      nil -> nil
      zone_number ->
        case Map.get(zones_map, to_string(zone_number)) do
          %{"name" => name} when is_binary(name) and name != "" -> name
          _ -> nil
        end
    end
  end

  defp check_adapters_connected do
    try do
      connection_status = SerialManager.get_connection_status()
      connection_status.adapter_1.connected && connection_status.adapter_2.connected
    rescue
      _ -> false
    end
  end

  defp get_current_mute_state(zone_num) do
    try do
      device = Devices.get_device!(1)
      mute_states = device.mute_states || %{}
      current_mute = Map.get(mute_states, to_string(zone_num), false)
      {:ok, current_mute}
    rescue
      error ->
        Logger.error("Failed to get mute state for zone #{zone_num}: #{inspect(error)}")
        {:error, "Database error"}
    end
  end

  defp update_zone_volume(zone_num, volume) do
    try do
      device = Devices.get_device!(1)
      current_volume_states = device.volume_states || %{}
      updated_volume_states = Map.put(current_volume_states, to_string(zone_num), volume)

      case Devices.update_device(device, %{volume_states: updated_volume_states}) do
        {:ok, _updated_device} ->
          # Send command to hardware
          send_volume_command(zone_num, volume)

          # Publish MQTT update
          publish_zone_update(zone_num)

          :ok

        {:error, changeset} ->
          Logger.error("Failed to update zone #{zone_num} volume: #{inspect(changeset)}")
          {:error, "Database update failed"}
      end
    rescue
      error ->
        Logger.error("Failed to update zone volume: #{inspect(error)}")
        {:error, "Database error"}
    end
  end

  defp update_zone_mute(zone_num, muted) do
    try do
      device = Devices.get_device!(1)
      current_mute_states = device.mute_states || %{}
      updated_mute_states = Map.put(current_mute_states, to_string(zone_num), muted)

      case Devices.update_device(device, %{mute_states: updated_mute_states}) do
        {:ok, _updated_device} ->
          # Send command to hardware
          send_mute_command(zone_num, muted)

          # Publish MQTT update
          publish_zone_update(zone_num)

          :ok

        {:error, changeset} ->
          Logger.error("Failed to update zone #{zone_num} mute: #{inspect(changeset)}")
          {:error, "Database update failed"}
      end
    rescue
      error ->
        Logger.error("Failed to update zone mute: #{inspect(error)}")
        {:error, "Database error"}
    end
  end

  defp update_zone_source(zone_num, source) do
    try do
      device = Devices.get_device!(1)
      current_source_states = device.source_states || %{}
      updated_source_states = Map.put(current_source_states, to_string(zone_num), source)

      case Devices.update_device(device, %{source_states: updated_source_states}) do
        {:ok, _updated_device} ->
          # Send command to hardware (if needed)
          send_source_command(zone_num, source)

          # Publish MQTT update
          publish_zone_update(zone_num)

          :ok

        {:error, changeset} ->
          Logger.error("Failed to update zone #{zone_num} source: #{inspect(changeset)}")
          {:error, "Database update failed"}
      end
    rescue
      error ->
        Logger.error("Failed to update zone source: #{inspect(error)}")
        {:error, "Database error"}
    end
  end

  defp send_volume_command(zone_num, volume) do
    try do
      # Convert 0-based zone to 1-based for HexCommandManager
      zone_manager_zone = zone_num + 1

      case HexCommandManager.get_volume_command(zone_manager_zone, volume) do
        {:ok, hex_chunks} ->
          send_hex_chunks(:adapter_1, hex_chunks, "volume")
          Logger.info("Sent volume command for zone #{zone_num} to #{volume}%")

        {:error, reason} ->
          Logger.error("Failed to get volume command for zone #{zone_num}: #{reason}")
      end
    rescue
      error ->
        Logger.error("Failed to send volume command: #{inspect(error)}")
    end
  end

  defp send_mute_command(zone_num, muted) do
    try do
      command = if muted, do: "mute_zone_#{zone_num}", else: "unmute_zone_#{zone_num}"

      case command do
        "mute_zone_" <> _ ->
          case HexCommandManager.get_mute_command(zone_num) do
            {:ok, hex_chunks} ->
              send_hex_chunks(:adapter_1, hex_chunks, "mute")
              Logger.info("Sent mute command for zone #{zone_num}")

            {:error, reason} ->
              Logger.error("Failed to get mute command for zone #{zone_num}: #{reason}")
          end

        "unmute_zone_" <> _ ->
          case HexCommandManager.get_unmute_command(zone_num) do
            {:ok, hex_chunks} ->
              send_hex_chunks(:adapter_1, hex_chunks, "unmute")
              Logger.info("Sent unmute command for zone #{zone_num}")

            {:error, reason} ->
              Logger.error("Failed to get unmute command for zone #{zone_num}: #{reason}")
          end
      end
    rescue
      error ->
        Logger.error("Failed to send mute command: #{inspect(error)}")
    end
  end

  defp send_source_command(zone_num, source) do
    # Source commands would be implemented here if needed
    # For now, just log the change
    Logger.info("Zone #{zone_num} source changed to #{source}")
  end

  defp send_hex_chunks(adapter, hex_chunks, command_type) do
    Enum.each(hex_chunks, fn chunk ->
      case SerialManager.send_command(adapter, chunk) do
        :ok ->
          Logger.debug("Sent #{command_type} chunk: #{inspect(chunk)}")
        {:error, reason} ->
          Logger.error("Failed to send #{command_type} chunk: #{reason}")
      end
    end)
  end

  defp publish_zone_update(zone_num) do
    try do
      case load_zone_state(zone_num) do
        {:ok, zone} ->
          AmpBridge.MQTTClient.publish_zone_state(zone_num, zone)
        {:error, _reason} ->
          Logger.warning("Failed to load zone state for MQTT update: #{zone_num}")
      end
    rescue
      error ->
        Logger.error("Failed to publish zone update: #{inspect(error)}")
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

  # Health check helper functions
  defp check_database do
    try do
      # Try to query the database
      Devices.get_device(1)
      :ready
    rescue
      _ -> :not_ready
    end
  end

  defp check_mqtt do
    try do
      # Check if MQTT client is running
      case Process.whereis(AmpBridge.MQTTClient) do
        nil -> :not_ready
        pid when is_pid(pid) -> :ready
      end
    rescue
      _ -> :not_ready
    end
  end

  defp check_serial_manager do
    try do
      # Check if Serial Manager is running
      case Process.whereis(AmpBridge.SerialManager) do
        nil -> :not_ready
        pid when is_pid(pid) -> :ready
      end
    rescue
      _ -> :not_ready
    end
  end

  defp check_usb_scanner do
    try do
      # Check if USB Device Scanner is running
      case Process.whereis(AmpBridge.USBDeviceScanner) do
        nil -> :not_ready
        pid when is_pid(pid) -> :ready
      end
    rescue
      _ -> :not_ready
    end
  end

  defp check_hardware_manager do
    try do
      # Check if Hardware Manager is running
      case Process.whereis(AmpBridge.HardwareManager) do
        nil -> :not_ready
        pid when is_pid(pid) -> :ready
      end
    rescue
      _ -> :not_ready
    end
  end
end
