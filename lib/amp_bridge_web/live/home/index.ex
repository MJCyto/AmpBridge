defmodule AmpBridgeWeb.HomeLive.Index do
  use AmpBridgeWeb, :live_view
  require Logger

  alias AmpBridge.Devices
  alias AmpBridge.HexCommandManager
  alias AmpBridge.SerialManager
  alias AmpBridge.ZoneGroups
  alias AmpBridge.ZoneManager
  alias AmpBridge.ZoneGroupManager
  alias AmpBridgeWeb.USBInitComponent
  import AmpBridgeWeb.PageWrapper

  @impl true
  def mount(_params, _session, socket) do
    is_initialized = AmpBridge.USBDeviceScanner.is_system_initialized()

    if !is_initialized do
      Logger.info("System not initialized, redirecting to init page")
      {:ok, push_navigate(socket, to: ~p"/init")}
    else
      connection_status =
        try do
          SerialManager.get_connection_status()
        rescue
          _ -> %{adapter_1: %{connected: false}, adapter_2: %{connected: false}}
        catch
          :exit, _ -> %{adapter_1: %{connected: false}, adapter_2: %{connected: false}}
        end

      system_status = get_system_status()

      socket = assign(socket,
        adapter_1_connected: connection_status.adapter_1.connected,
        adapter_2_connected: connection_status.adapter_2.connected,
        advanced_mode: false,
        show_group_management: false,
        all_messages: [],
        database_connected: system_status.database_connected,
        mqtt_connected: system_status.mqtt_connected,
        mqtt_broker: system_status.mqtt_broker,
        mqtt_message_count: system_status.mqtt_message_count,
        system_uptime: system_status.system_uptime,
        memory_usage: system_status.memory_usage,
        last_command_time: system_status.last_command_time,
        last_command_details: system_status.last_command_details,
        error_count: system_status.error_count,
        services_ready: check_services_ready()
      )

      if connected?(socket) do
        Phoenix.PubSub.subscribe(AmpBridge.PubSub, "device_updates")

        case Devices.list_devices() do
          devices when is_list(devices) ->
            Logger.info("DEVICE_CARD_DEBUG: HomeLive loaded #{length(devices)} devices")

            {configured_zones, zone_mute_states, zone_source_states, zone_sources, zone_volume_states, zone_mapping} =
              load_zone_configuration()

            zone_groups = ZoneGroups.list_zone_groups(1)

            {:ok,
             assign(socket,
               page_title: "AmpBridge",
               devices: devices,
               error: nil,
               configured_zones: configured_zones,
               zone_mute_states: zone_mute_states,
               zone_source_states: zone_source_states,
               zone_sources: zone_sources,
               zone_volume_states: zone_volume_states,
               zone_mapping: zone_mapping,
               zone_groups: zone_groups
             )}

          _ ->
            Logger.warning("DEVICE_CARD_DEBUG: HomeLive failed to load devices")
            {configured_zones, zone_mute_states, zone_source_states, zone_sources, zone_volume_states, zone_mapping} =
              load_zone_configuration()

            zone_groups = ZoneGroups.list_zone_groups(1)

            {:ok,
             assign(socket,
               page_title: "AmpBridge",
               devices: [],
               error: "Unable to load devices",
               configured_zones: configured_zones,
               zone_mute_states: zone_mute_states,
               zone_source_states: zone_source_states,
               zone_sources: zone_sources,
               zone_volume_states: zone_volume_states,
               zone_mapping: zone_mapping,
               zone_groups: zone_groups
             )}
        end
      else
        {:ok,
         assign(socket,
           page_title: "AmpBridge",
           devices: [],
           error: nil,
           configured_zones: [],
           zone_mute_states: %{},
           zone_source_states: %{},
           zone_sources: %{},
           zone_volume_states: %{},
           zone_mapping: %{},
           zone_groups: []
         )}
      end
    end
  rescue
    error ->
      Logger.error("DEVICE_CARD_DEBUG: HomeLive mount error: #{inspect(error)}")
      system_status = get_system_status()
      {:ok,
       assign(socket,
         page_title: "AmpBridge",
         devices: [],
         error: "Database connection failed",
         configured_zones: [],
         zone_mute_states: %{},
         zone_source_states: %{},
         zone_sources: %{},
         zone_volume_states: %{},
         advanced_mode: false,
         all_messages: [],
         current_path: "/",
         database_connected: system_status.database_connected,
         mqtt_connected: system_status.mqtt_connected,
         mqtt_broker: system_status.mqtt_broker,
         mqtt_message_count: system_status.mqtt_message_count,
         system_uptime: system_status.system_uptime,
         memory_usage: system_status.memory_usage,
         last_command_time: system_status.last_command_time,
         error_count: system_status.error_count
       )}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, uri: uri)}
  end

  @impl true
  def handle_event(
        "slider_change",
        %{"deviceId" => device_id, "setting" => setting, "value" => value},
        socket
      ) do
    Logger.info(
      "DEVICE_CARD_DEBUG: HomeLive received slider_change event for device_id: #{device_id}, setting: #{setting}, value: #{value}"
    )

    # Handle device setting update from JavaScript slider
    case update_device_setting(device_id, setting, value) do
      {:ok, updated_device} ->
        Logger.info(
          "DEVICE_CARD_DEBUG: HomeLive successfully updated device #{device_id} setting #{setting} to #{value}"
        )

        # Update the device in the list
        updated_devices =
          Enum.map(socket.assigns.devices, fn device ->
            if device.id == String.to_integer(device_id) do
              updated_device
            else
              device
            end
          end)

        # Broadcast the update to all other users
        Phoenix.PubSub.broadcast(
          AmpBridge.PubSub,
          "device_updates",
          {:device_updated, updated_device}
        )

        {:noreply, assign(socket, devices: updated_devices)}

      {:error, changeset} ->
        Logger.error(
          "DEVICE_CARD_DEBUG: HomeLive failed to update device #{device_id} setting #{setting}: #{inspect(changeset)}"
        )

        # Handle error (could show flash message)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("refresh_devices", _params, socket) do
    connection_status = SerialManager.get_connection_status()
    system_status = get_system_status()

    {:noreply,
     assign(socket,
       adapter_1_connected: connection_status.adapter_1.connected,
       adapter_2_connected: connection_status.adapter_2.connected,
       database_connected: system_status.database_connected,
       mqtt_connected: system_status.mqtt_connected,
       mqtt_broker: system_status.mqtt_broker,
       mqtt_message_count: system_status.mqtt_message_count,
       system_uptime: system_status.system_uptime,
       memory_usage: system_status.memory_usage,
       last_command_time: system_status.last_command_time,
       last_command_details: system_status.last_command_details,
       error_count: system_status.error_count
     )}
  end

  @impl true
  def handle_event("toggle_advanced_mode", _params, socket) do
    new_advanced_mode = !socket.assigns.advanced_mode

    # Subscribe/unsubscribe to serial data based on advanced mode
    if new_advanced_mode do
      Phoenix.PubSub.subscribe(AmpBridge.PubSub, "serial_data")
    else
      Phoenix.PubSub.unsubscribe(AmpBridge.PubSub, "serial_data")
    end

    {:noreply, assign(socket, advanced_mode: new_advanced_mode)}
  end

  @impl true
  def handle_event("toggle_group_management", _params, socket) do
    new_show_group_management = !socket.assigns.show_group_management
    {:noreply, assign(socket, show_group_management: new_show_group_management)}
  end

  @impl true
  def handle_event("clear_messages", _params, socket) do
    {:noreply, assign(socket, all_messages: [])}
  end

  @impl true
  def handle_event("copy_to_console", _params, socket) do
    if length(socket.assigns.all_messages) > 0 do
      # Create a simplified array structure for easy analysis
      messages_data =
        socket.assigns.all_messages
        # Show in chronological order
        |> Enum.reverse()
        |> Enum.map(fn message ->
          %{
            timestamp: message.timestamp,
            hex: message.hex,
            size: message.size,
            adapter: message.adapter,
            adapter_name: message.adapter_name,
            adapter_color: message.adapter_color
          }
        end)

      # Send to client for console log
      {:noreply,
       socket
       |> put_flash(
         :info,
         "Message log data logged to console! Check browser console and copy the data for analysis."
       )
       |> push_event("copy_messages_to_console", %{messages: messages_data})}
    else
      {:noreply, put_flash(socket, :error, "No messages to copy")}
    end
  end

  @impl true
  def handle_event("connect_adapter", %{"adapter" => adapter, "device_path" => device_path}, socket) do
    adapter_atom = String.to_atom(adapter)

    case SerialManager.connect_adapter(adapter_atom, device_path) do
      {:ok, _pid} ->
        Logger.info("Successfully connected #{adapter} to #{device_path}")

        connection_status = SerialManager.get_connection_status()

        {:noreply,
         put_flash(socket, :info, "#{adapter} connected successfully")
         |> assign(
           adapter_1_connected: connection_status.adapter_1.connected,
           adapter_2_connected: connection_status.adapter_2.connected
         )}

      {:error, reason} ->
        Logger.error("Failed to connect #{adapter}: #{reason}")
        {:noreply, put_flash(socket, :error, "Failed to connect #{adapter}: #{reason}")}
    end
  end

  @impl true
  def handle_event("disconnect_adapter", %{"adapter" => adapter}, socket) do
    adapter_atom = String.to_atom(adapter)

    case SerialManager.disconnect_adapter(adapter_atom) do
      :ok ->
        Logger.info("Successfully disconnected #{adapter}")

        connection_status = SerialManager.get_connection_status()

        {:noreply,
         put_flash(socket, :info, "#{adapter} disconnected")
         |> assign(
           adapter_1_connected: connection_status.adapter_1.connected,
           adapter_2_connected: connection_status.adapter_2.connected
         )}

      {:error, reason} ->
        Logger.error("Failed to disconnect #{adapter}: #{reason}")
        {:noreply, put_flash(socket, :error, "Failed to disconnect #{adapter}: #{reason}")}
    end
  end

  @impl true
  def handle_event("update_adapter_settings", %{"adapter" => adapter, "settings" => settings}, socket) do
    adapter_atom = String.to_atom(adapter)

    settings_map =
      settings
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
      |> Enum.into(%{})

    case SerialManager.set_adapter_settings(adapter_atom, settings_map) do
      :ok ->
        Logger.info("Updated settings for #{adapter}")
        {:noreply, put_flash(socket, :info, "#{adapter} settings updated")}

      {:error, reason} ->
        Logger.error("Failed to update settings for #{adapter}: #{reason}")
        {:noreply, put_flash(socket, :error, "Failed to update #{adapter} settings: #{reason}")}
    end
  end

  @impl true
  def handle_info({:update_adapter_name, adapter, name}, socket) do
    Logger.info("Received adapter name update: #{adapter} -> #{name}")

    case Devices.get_device(1) do
      nil ->
        {:noreply, put_flash(socket, :error, "Device not found")}

      device ->
        field = if adapter == "adapter_1", do: :adapter_1_name, else: :adapter_2_name
        attrs = %{field => name}

        case Devices.update_device(device, attrs) do
          {:ok, _updated_device} ->
            Logger.info("Updated #{adapter} name to #{name}")
            {:noreply, put_flash(socket, :info, "#{String.capitalize(adapter)} name updated to #{name}")}

          {:error, changeset} ->
            Logger.error("Failed to update #{adapter} name: #{inspect(changeset)}")
            {:noreply, put_flash(socket, :error, "Failed to update #{adapter} name")}
        end
    end
  end

  @impl true
  def handle_info({:save_adapter_roles, _amp_id}, socket) do
    Logger.info("Received save adapter roles request")

    case Devices.get_device(1) do
      nil ->
        {:noreply, put_flash(socket, :error, "Device not found")}

      device ->
        attrs = %{
          auto_detection_complete: true,
          adapter_1_role: "controller",
          adapter_2_role: "amp"
        }

        case Devices.update_device(device, attrs) do
          {:ok, _updated_device} ->
            Logger.info("Adapter roles saved successfully")
            {:noreply, put_flash(socket, :info, "Adapter roles saved! Auto-detection complete.")}

          {:error, changeset} ->
            Logger.error("Failed to save adapter roles: #{inspect(changeset)}")
            {:noreply, put_flash(socket, :error, "Failed to save adapter roles")}
        end
    end
  end

  @impl true
  def handle_info({:start_auto_detection, _amp_id}, socket) do
    Logger.info("Received start auto-detection request")
    Phoenix.PubSub.subscribe(AmpBridge.PubSub, "serial_data")
    {:noreply, put_flash(socket, :info, "Auto-detection started - send commands from your controller")}
  end

  @impl true
  def handle_info({:stop_auto_detection, _amp_id}, socket) do
    Logger.info("Received stop auto-detection request")
    Phoenix.PubSub.unsubscribe(AmpBridge.PubSub, "serial_data")
    {:noreply, put_flash(socket, :info, "Auto-detection stopped")}
  end

  @impl true
  def handle_info({:serial_data, data, decoded, adapter_info}, socket) do
    Logger.info("Auto-detection: Received data from #{adapter_info.adapter} - #{AmpBridge.SerialManager.format_hex(data)}")

    # If in advanced mode, collect messages for the log
    if socket.assigns.advanced_mode do
      # Create message structure similar to serial analysis
      message = %{
        timestamp: DateTime.utc_now(),
        hex: AmpBridge.SerialManager.format_hex(data),
        size: byte_size(data),
        decoded: decoded,
        adapter: adapter_info.adapter,
        adapter_name: adapter_info.adapter_name || "Unknown",
        adapter_color: case adapter_info.adapter do
          :adapter_1 -> "blue"
          :adapter_2 -> "green"
          _ -> "grey"
        end
      }

      # Add to messages list (keep last 100 messages)
      updated_messages =
        [message | socket.assigns.all_messages]
        |> Enum.take(100)

      {:noreply, assign(socket, all_messages: updated_messages)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:edit_device, device_id}, socket) do
    Logger.info(
      "DEVICE_CARD_DEBUG: HomeLive received edit_device message for device_id: #{device_id}"
    )

    # Handle edit request from component
    # You could redirect to edit page or open modal
    {:noreply, socket}
  end

  @impl true
  def handle_info({:delete_device, device_id}, socket) do
    Logger.info(
      "DEVICE_CARD_DEBUG: HomeLive received delete_device message for device_id: #{device_id}"
    )

    # Handle delete request from component
    case Devices.delete_device(Devices.get_device!(device_id)) do
      {:ok, _deleted_device} ->
        Logger.info("DEVICE_CARD_DEBUG: HomeLive successfully deleted device #{device_id}")
        # Remove device from list and re-render
        updated_devices = Enum.reject(socket.assigns.devices, &(&1.id == device_id))

        # Broadcast the deletion to all other users
        Phoenix.PubSub.broadcast(
          AmpBridge.PubSub,
          "device_updates",
          {:device_deleted, device_id}
        )

        {:noreply, assign(socket, devices: updated_devices)}

      {:error, changeset} ->
        Logger.error(
          "DEVICE_CARD_DEBUG: HomeLive failed to delete device #{device_id}: #{inspect(changeset)}"
        )

        # Handle error (could show flash message)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:update_device_setting, device_id, setting, value}, socket) do
    Logger.info(
      "DEVICE_CARD_DEBUG: HomeLive received update_device_setting message for device_id: #{device_id}, setting: #{setting}, value: #{value}"
    )

    # Handle device setting update from component
    case update_device_setting(device_id, setting, value) do
      {:ok, updated_device} ->
        Logger.info(
          "DEVICE_CARD_DEBUG: HomeLive successfully updated device #{device_id} setting #{setting} to #{value}"
        )

        # Update the device in the list
        updated_devices =
          Enum.map(socket.assigns.devices, fn device ->
            if device.id == device_id do
              updated_device
            else
              device
            end
          end)

        # Broadcast the update to all other users
        Phoenix.PubSub.broadcast(
          AmpBridge.PubSub,
          "device_updates",
          {:device_updated, updated_device}
        )

        {:noreply, assign(socket, devices: updated_devices)}

      {:error, changeset} ->
        Logger.error(
          "DEVICE_CARD_DEBUG: HomeLive failed to update device #{device_id} setting #{setting}: #{inspect(changeset)}"
        )

        # Handle error (could show flash message)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:update_output_control, device_id, output_index, field, value}, socket) do
    Logger.info(
      "DEVICE_CARD_DEBUG: HomeLive received update_output_control message for device_id: #{device_id}, output_index: #{output_index}, field: #{field}, value: #{value}"
    )

    # Handle output control update from component
    case update_output_control(device_id, output_index, field, value) do
      {:ok, updated_device} ->
        Logger.info(
          "DEVICE_CARD_DEBUG: HomeLive successfully updated device #{device_id} output #{output_index} #{field} to #{value}"
        )

        # Update the device in the list
        updated_devices =
          Enum.map(socket.assigns.devices, fn device ->
            if device.id == device_id do
              updated_device
            else
              device
            end
          end)

        # Broadcast the update to all other users
        Phoenix.PubSub.broadcast(
          AmpBridge.PubSub,
          "device_updates",
          {:device_updated, updated_device}
        )

        {:noreply, assign(socket, devices: updated_devices)}

      {:error, changeset} ->
        Logger.error(
          "DEVICE_CARD_DEBUG: HomeLive failed to update device #{device_id} output #{output_index} #{field}: #{inspect(changeset)}"
        )

        # Handle error (could show flash message)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:device_updated, updated_device}, socket) do
    Logger.info(
      "DEVICE_CARD_DEBUG: HomeLive received device_updated broadcast for device_id: #{updated_device.id}"
    )

    updated_devices =
      Enum.map(socket.assigns.devices, fn device ->
        if device.id == updated_device.id do
          updated_device
        else
          device
        end
      end)

    {:noreply, assign(socket, devices: updated_devices)}
  end

  @impl true
  def handle_info({:device_created, new_device}, socket) do
    Logger.info(
      "DEVICE_CARD_DEBUG: HomeLive received device_created broadcast for device_id: #{new_device.id}"
    )

    updated_devices = [new_device | socket.assigns.devices]
    {:noreply, assign(socket, devices: updated_devices)}
  end

  @impl true
  def handle_info({:device_deleted, device_id}, socket) do
    Logger.info(
      "DEVICE_CARD_DEBUG: HomeLive received device_deleted broadcast for device_id: #{device_id}"
    )

    updated_devices = Enum.reject(socket.assigns.devices, &(&1.id == device_id))
    {:noreply, assign(socket, devices: updated_devices)}
  end

  @impl true
  def handle_info({:zone_volume_changed, zone_id, volume}, socket) do
    Logger.info("HomeLive received zone_volume_changed broadcast for zone #{zone_id}: #{volume}%")

    updated_volume_states = Map.put(socket.assigns.zone_volume_states, zone_id, volume)
    {:noreply, assign(socket, zone_volume_states: updated_volume_states)}
  end

  @impl true
  def handle_info({:zone_mute_changed, zone_id, muted}, socket) do
    Logger.info("HomeLive received zone_mute_changed broadcast for zone #{zone_id}: #{muted}")

    updated_mute_states = Map.put(socket.assigns.zone_mute_states, zone_id, muted)
    {:noreply, assign(socket, zone_mute_states: updated_mute_states)}
  end

  @impl true
  def handle_info({:zone_source_changed, zone_id, source}, socket) do
    Logger.info("HomeLive received zone_source_changed broadcast for zone #{zone_id}: #{source}")

    updated_source_states = Map.put(socket.assigns.zone_source_states, zone_id, source)
    {:noreply, assign(socket, zone_source_states: updated_source_states)}
  end

  @impl true
  def handle_info({:zone_volume_change, zone, volume}, socket) do
    Logger.info("HomeLive received zone_volume_change from component for zone #{zone}: #{volume}%")

    case update_zone_volume_state(zone, volume) do
      :ok ->
        current_mute_state = Map.get(socket.assigns.zone_mute_states, zone, false)
        updated_volume_states = Map.put(socket.assigns.zone_volume_states, zone, volume)

        {updated_mute_states, unmute_result} =
          if current_mute_state do
            case update_zone_mute_state(zone, false) do
              :ok ->
                {Map.put(socket.assigns.zone_mute_states, zone, false), :unmuted}
              {:error, _} ->
                {socket.assigns.zone_mute_states, :unmute_failed}
            end
          else
            {socket.assigns.zone_mute_states, :not_muted}
          end

        zone_manager_zone = zone + 1
        case HexCommandManager.get_volume_command(zone_manager_zone, volume) do
          {:ok, hex_chunks} ->
            send_hex_chunks(:adapter_1, hex_chunks, "volume")
          {:error, reason} ->
            Logger.error("Failed to get volume command: #{reason}")
        end

        volume_percent = "#{volume}%"
        command_name = "Zone #{zone} Volume #{volume_percent}"

        flash_message = case unmute_result do
          :unmuted -> "Setting #{command_name} and unmuting zone"
          :unmute_failed -> "Setting #{command_name} (failed to unmute zone)"
          :not_muted -> "Setting #{command_name}"
        end

        AmpBridge.MQTTClient.publish_zone_update(zone)

        {:noreply,
         socket
         |> assign(:zone_volume_states, updated_volume_states)
         |> assign(:zone_mute_states, updated_mute_states)
         |> assign(:last_command_time, Calendar.strftime(DateTime.utc_now(), "%H:%M:%S"))
         |> assign(:last_command_details, "Zone #{zone} Volume #{volume}%")
         |> put_flash(:info, flash_message)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update volume state in database")}
    end
  end

  @impl true
  def handle_info({:zone_mute_toggle, zone}, socket) do
    Logger.info("HomeLive received zone_mute_toggle from component for zone #{zone}")

    current_mute_state = Map.get(socket.assigns.zone_mute_states, zone, false)
    new_mute_state = !current_mute_state

    case update_zone_mute_state(zone, new_mute_state) do
      :ok ->
        command = if new_mute_state, do: "mute", else: "unmute"
        command_function = if new_mute_state, do: :get_mute_command, else: :get_unmute_command

        case apply(HexCommandManager, command_function, [zone]) do
          {:ok, hex_chunks} ->
            send_hex_chunks(:adapter_1, hex_chunks, command)

            updated_mute_states = Map.put(socket.assigns.zone_mute_states, zone, new_mute_state)
            command_name = String.replace(command, "_", " ") |> String.upcase()

            # Publish updated state to MQTT for Home Assistant
            AmpBridge.MQTTClient.publish_zone_update(zone)

            {:noreply,
             socket
             |> assign(:zone_mute_states, updated_mute_states)
             |> assign(:last_command_time, Calendar.strftime(DateTime.utc_now(), "%H:%M:%S"))
             |> assign(:last_command_details, "Zone #{zone} #{command_name}")
             |> put_flash(:info, "Sent #{command_name} command")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to get #{command} command: #{reason}")}
        end

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update mute state in database")}
    end
  end

  @impl true
  def handle_info({:zone_source_change, zone, source}, socket) do
    Logger.info("HomeLive received zone_source_change from component for zone #{zone}: #{source}")

    # Get the actual configured zone number for this 0-based zone index
    zone_manager_zone = Map.get(socket.assigns.zone_mapping, zone, zone + 1)

    # Get the device ID from the first device (same as used in command learning)
    device_id = case socket.assigns.devices do
      [device | _] -> device.id
      [] -> 1  # Fallback to 1 if no devices
    end

    # Parse source name to get source index or handle "Off"
    case source do
      "Off" ->
        # Send turn_off command using CommandLearner
        Logger.info("Sending turn_off command for zone #{zone} using device #{device_id}")
        case AmpBridge.CommandLearner.execute_command(device_id, "turn_off", zone) do
          {:ok, :command_sent} ->
            Logger.info("Turn off command sent successfully for zone #{zone}")
          {:error, reason} ->
            Logger.warning("Failed to send turn off command for zone #{zone}: #{reason}")
        end
      source_name when is_binary(source_name) ->
        # Extract index from "Source X" format (1-based to 0-based)
        case Regex.run(~r/Source (\d+)/, source_name) do
          [_, index_str] ->
            source_index = String.to_integer(index_str) - 1
            Logger.info("Sending change_source command for zone #{zone}, source_index #{source_index} using device #{device_id}")

            # Use CommandLearner to execute learned change_source commands
            case AmpBridge.CommandLearner.execute_command(device_id, "change_source", zone, source_index: source_index) do
              {:ok, :command_sent} ->
                Logger.info("Change source command sent successfully for zone #{zone}, source #{source_index}")
              {:error, reason} ->
                Logger.warning("Failed to send change source command for zone #{zone}, source #{source_index}: #{reason}")
                # Fallback to ZoneManager if learned command fails
                Logger.info("Falling back to ZoneManager for source change")
                AmpBridge.ZoneManager.change_zone_source(zone_manager_zone, source_index)
            end
          nil ->
            Logger.warning("Could not parse source name: #{source_name}")
        end
    end

    case update_zone_source_state(zone, source) do
      :ok ->
        updated_source_states = Map.put(socket.assigns.zone_source_states, zone, source)

        # Publish updated state to MQTT for Home Assistant
        AmpBridge.MQTTClient.publish_zone_update(zone)

        command_name = case source do
          "Off" -> "Zone #{zone} Turn Off"
          source_name when is_binary(source_name) ->
            case Regex.run(~r/Source (\d+)/, source_name) do
              [_, index_str] -> "Zone #{zone} Source #{index_str}"
              nil -> "Zone #{zone} Source #{source_name}"
            end
        end

        {:noreply,
         socket
         |> assign(:zone_source_states, updated_source_states)
         |> assign(:last_command_time, Calendar.strftime(DateTime.utc_now(), "%H:%M:%S"))
         |> assign(:last_command_details, command_name)
         |> put_flash(:info, "Sent #{command_name} command")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update source state in database")}
    end
  end

  @impl true
  def handle_info({:zone_volume_button, zone, command}, socket) do
    Logger.info("HomeLive received zone_volume_button from component for zone #{zone}: #{command}")

    target_volume =
      case command do
        "volume_0" -> 0
        "volume_25" -> 25
        "volume_50" -> 50
        "volume_75" -> 75
        "volume_100" -> 100
        _ -> nil
      end

    if target_volume do
      zone_manager_zone = zone + 1

      case HexCommandManager.get_volume_command(zone_manager_zone, target_volume) do
        {:ok, hex_chunks} ->
          send_hex_chunks(:adapter_1, hex_chunks, "volume")

          case update_zone_volume_state(zone, target_volume) do
            :ok ->
              current_mute_state = Map.get(socket.assigns.zone_mute_states, zone, false)
              updated_volume_states = Map.put(socket.assigns.zone_volume_states, zone, target_volume)

              {updated_mute_states, unmute_result} =
                if current_mute_state do
                  case update_zone_mute_state(zone, false) do
                    :ok ->
                      {Map.put(socket.assigns.zone_mute_states, zone, false), :unmuted}
                    {:error, _} ->
                      {socket.assigns.zone_mute_states, :unmute_failed}
                  end
                else
                  {socket.assigns.zone_mute_states, :not_muted}
                end

              volume_percent = "#{target_volume}%"
              command_name = "Zone #{zone} Volume #{volume_percent}"

              flash_message = case unmute_result do
                :unmuted -> "Setting #{command_name} and unmuting zone"
                :unmute_failed -> "Setting #{command_name} (failed to unmute zone)"
                :not_muted -> "Setting #{command_name}"
              end

              # Publish updated state to MQTT for Home Assistant
              AmpBridge.MQTTClient.publish_zone_update(zone)

              {:noreply,
               socket
               |> assign(:zone_volume_states, updated_volume_states)
               |> assign(:zone_mute_states, updated_mute_states)
               |> assign(:last_command_time, Calendar.strftime(DateTime.utc_now(), "%H:%M:%S"))
               |> assign(:last_command_details, command_name)
               |> put_flash(:info, flash_message)}

            {:error, _reason} ->
              {:noreply, put_flash(socket, :error, "Failed to update volume state in database")}
          end

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to get volume command: #{reason}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Unknown volume command: #{command}")}
    end
  end

  # Handle Tortoise MQTT client messages
  def handle_info({{Tortoise, _client_id}, _ref, :ok}, socket) do
    {:noreply, socket}
  end

  def handle_info({{Tortoise, _client_id}, _ref, {:ok, _result}}, socket) do
    {:noreply, socket}
  end

  def handle_info({{Tortoise, _client_id}, _ref, {:error, reason}}, socket) do
    Logger.error("MQTT operation failed: #{inspect(reason)}")
    {:noreply, put_flash(socket, :error, "MQTT operation failed: #{inspect(reason)}")}
  end

  defp update_device_setting(device_id, setting, value) do
    Logger.info(
      "DEVICE_CARD_DEBUG: update_device_setting called with device_id: #{device_id}, setting: #{setting}, value: #{value}"
    )

    device = Devices.get_device!(device_id)

    # Update settings in the settings map
    current_settings = device.settings || %{}
    updated_settings = Map.put(current_settings, setting, value)

    Logger.info(
      "DEVICE_CARD_DEBUG: Updating device settings from #{inspect(current_settings)} to #{inspect(updated_settings)}"
    )

    Devices.update_device(device, %{settings: updated_settings})
  end

  defp update_output_control(device_id, output_index, field, value) do
    Logger.info(
      "DEVICE_CARD_DEBUG: update_output_control called with device_id: #{device_id}, output_index: #{output_index}, field: #{field}, value: #{value}"
    )

    device = Devices.get_device!(device_id)
    current_outputs = device.outputs || []

    # Update the specific output field
    updated_outputs =
      List.update_at(current_outputs, output_index, fn output ->
        # Convert struct to map, update the field, then convert back to struct
        output
        |> Map.from_struct()
        |> Map.put(String.to_existing_atom(field), String.to_integer(value))
        |> then(fn attrs -> struct(AmpBridge.AudioDevice.InputOutput, attrs) end)
      end)

    Logger.info(
      "DEVICE_CARD_DEBUG: Updating device outputs from #{inspect(current_outputs)} to #{inspect(updated_outputs)}"
    )

    # Convert all outputs to maps since embeds_many expects maps, not structs
    outputs_as_maps = Enum.map(updated_outputs, &Map.from_struct/1)

    Devices.update_device(device, %{outputs: outputs_as_maps})
  end

  # Helper function to load zone configuration (similar to serial analysis)
  defp load_zone_configuration do
    # Load device configuration from database
    device = Devices.get_device(1)

    if device && device.zones && map_size(device.zones) > 0 do
      # Use the actually configured zones from the database
      zones_map = device.zones

      # Extract zone numbers and convert to 0-based indexing
      # Zones are stored with string keys ("0", "1", "2", "3") representing 0-based indices
      configured_zones =
        zones_map
        |> Map.keys()
        |> Enum.map(&String.to_integer/1)
        |> Enum.filter(fn zone -> zone >= 0 end)
        |> Enum.sort()

      # Load states from database, with fallback to defaults
      mute_states =
        configured_zones
        |> Enum.map(fn zone ->
          # Load from database, fallback to false
          db_mute_state = Map.get(device.mute_states || %{}, to_string(zone), false)
          {zone, db_mute_state}
        end)
        |> Enum.into(%{})

      source_states =
        configured_zones
        |> Enum.map(fn zone ->
          # Load from database, fallback to nil
          db_source_state = Map.get(device.source_states || %{}, to_string(zone), nil)
          {zone, db_source_state}
        end)
        |> Enum.into(%{})

      volume_states =
        configured_zones
        |> Enum.map(fn zone ->
          # Load from database, fallback to 50
          db_volume_state = Map.get(device.volume_states || %{}, to_string(zone), 50)
          {zone, db_volume_state}
        end)
        |> Enum.into(%{})

      # Create zone sources based on configured sources
      sources_map = device.sources || %{}
      sources_list =
        sources_map
        |> Map.keys()
        |> Enum.sort()
        |> Enum.map(fn key ->
          source_data = Map.get(sources_map, key)
          Map.get(source_data, "name", "Source #{String.to_integer(key) + 1}")
        end)

      zone_sources_map =
        configured_zones
        |> Enum.map(fn zone ->
          {zone, sources_list}
        end)
        |> Enum.into(%{})

      # Create zone mapping for commands (1-based zone numbers)
      zone_mapping =
        configured_zones
        |> Enum.with_index(1)
        |> Enum.into(%{})

      {configured_zones, mute_states, source_states, zone_sources_map, volume_states, zone_mapping}
    else
      # Fallback to default zones 0-7 if no device or no zones configured (0-based)
      default_zones = [0, 1, 2, 3, 4, 5, 6, 7]

      mute_states =
        default_zones
        |> Enum.map(fn zone -> {zone, false} end)
        |> Enum.into(%{})

      source_states =
        default_zones
        |> Enum.map(fn zone -> {zone, nil} end)
        |> Enum.into(%{})

      volume_states =
        default_zones
        |> Enum.map(fn zone -> {zone, 50} end)
        |> Enum.into(%{})

      zone_sources = %{
        0 => ["Source 1", "Source 2"],
        1 => [],
        2 => [],
        3 => [],
        4 => [],
        5 => [],
        6 => [],
        7 => []
      }

      # Create simple zone mapping for default zones
      zone_mapping = %{0 => 1, 1 => 2, 2 => 3, 3 => 4, 4 => 5, 5 => 6, 6 => 7, 7 => 8}

      {default_zones, mute_states, source_states, zone_sources, volume_states, zone_mapping}
    end
  end

  # Helper function to get zone name from device config
  defp get_zone_name(device_config, zone) do
    if device_config && device_config.zones do
      # Get the configured zone numbers and sort them
      configured_zones = device_config.zones
      |> Map.keys()
      |> Enum.map(&String.to_integer/1)
      |> Enum.sort()

      # Map 0-based zone index to the corresponding configured zone number
      case Enum.at(configured_zones, zone) do
        nil -> nil
        zone_number ->
          case Map.get(device_config.zones, to_string(zone_number)) do
            %{"name" => name} when is_binary(name) and name != "" -> name
            _ -> nil
          end
      end
    else
      nil
    end
  end



  # Helper function to send hex chunks one after another with no delay
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

  # Helper function to update zone mute state in database
  defp update_zone_mute_state(zone, muted) do
    device = Devices.get_device!(1)
    current_mute_states = device.mute_states || %{}
    updated_mute_states = Map.put(current_mute_states, to_string(zone), muted)

    case Devices.update_device(device, %{mute_states: updated_mute_states}) do
      {:ok, _updated_device} ->
        Logger.info("Updated zone #{zone} mute state to #{muted} in database")
        :ok
      {:error, changeset} ->
        Logger.error("Failed to update zone #{zone} mute state: #{inspect(changeset)}")
        {:error, changeset}
    end
  end

  # Helper function to update zone source state in database
  defp update_zone_source_state(zone, source) do
    device = Devices.get_device!(1)
    current_source_states = device.source_states || %{}

    # Store nil instead of "Off" for turned off zones
    stored_source = case source do
      "Off" -> nil
      source when is_binary(source) -> source
      _ -> nil
    end

    updated_source_states = Map.put(current_source_states, to_string(zone), stored_source)

    case Devices.update_device(device, %{source_states: updated_source_states}) do
      {:ok, _updated_device} ->
        Logger.info("Updated zone #{zone} source state to #{stored_source || "Off"} in database")
        :ok
      {:error, changeset} ->
        Logger.error("Failed to update zone #{zone} source state: #{inspect(changeset)}")
        {:error, changeset}
    end
  end

  # Helper function to update zone volume state in database
  defp update_zone_volume_state(zone, volume) do
    device = Devices.get_device!(1)
    current_volume_states = device.volume_states || %{}
    updated_volume_states = Map.put(current_volume_states, to_string(zone), volume)

    case Devices.update_device(device, %{volume_states: updated_volume_states}) do
      {:ok, _updated_device} ->
        Logger.info("Updated zone #{zone} volume state to #{volume} in database")
        :ok
      {:error, changeset} ->
        Logger.error("Failed to update zone #{zone} volume state: #{inspect(changeset)}")
        {:error, changeset}
    end
  end

  # Helper function to get system status information
  defp get_system_status do
    # Check database connection
    database_connected =
      try do
        case Devices.list_devices() do
          devices when is_list(devices) -> true
          _ -> false
        end
      rescue
        _ -> false
      catch
        :exit, _ -> false
      end

    # Check MQTT connection (simplified check)
    mqtt_connected =
      try do
        # Check if MQTT client is running
        case Process.whereis(AmpBridge.MQTTClient) do
          nil -> false
          _pid -> true
        end
      rescue
        _ -> false
      catch
        :exit, _ -> false
      end

    # Get MQTT broker info (if available)
    mqtt_broker =
      try do
        # This would need to be implemented in MQTTClient
        # For now, return a placeholder
        "localhost:1883"
      rescue
        _ -> nil
      end

    # Get system uptime
    system_uptime =
      try do
        # Get system uptime in a readable format
        {uptime_seconds, _} = :erlang.statistics(:wall_clock)
        # Convert from milliseconds to seconds and format
        format_uptime(div(uptime_seconds, 1000))
      rescue
        _ -> "Unknown"
      end

    # Get memory usage
    memory_usage =
      try do
        memory = :erlang.memory()
        total_mb = memory[:total] / 1024 / 1024
        "#{Float.round(total_mb, 1)} MB"
      rescue
        _ -> "Unknown"
      end

    # Get last command time and details (simplified for now)
    last_command_time = "None"
    last_command_details = "No commands sent"

    # Get error count (placeholder for now)
    error_count =
      try do
        # This would need to be tracked in the system
        0
      rescue
        _ -> 0
      end

    %{
      database_connected: database_connected,
      mqtt_connected: mqtt_connected,
      mqtt_broker: mqtt_broker,
      mqtt_message_count: 0, # Placeholder
      system_uptime: system_uptime,
      memory_usage: memory_usage,
      last_command_time: last_command_time,
      last_command_details: last_command_details,
      error_count: error_count
    }
  end

  # Helper function to check if critical services are ready
  defp check_services_ready do
    try do
      # Check if ZoneManager is running and responsive
      ZoneManager.get_all_zone_volumes()

      # Check if ZoneGroupManager is running and responsive
      ZoneGroupManager.get_group_state(1)

      true
    rescue
      _ -> false
    catch
      :exit, _ -> false
    end
  end

  # Helper function to format uptime
  defp format_uptime(seconds) do
    days = div(seconds, 86400)
    hours = div(rem(seconds, 86400), 3600)
    minutes = div(rem(seconds, 3600), 60)

    cond do
      days > 0 -> "#{days}d #{hours}h #{minutes}m"
      hours > 0 -> "#{hours}h #{minutes}m"
      true -> "#{minutes}m"
    end
  end

end
