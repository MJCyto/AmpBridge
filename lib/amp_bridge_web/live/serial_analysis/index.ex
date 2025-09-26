defmodule AmpBridgeWeb.SerialAnalysisLive.Index do
  use AmpBridgeWeb, :live_view
  require Logger

  import AmpBridgeWeb.SerialAnalysis.AdapterCard

  alias AmpBridge.CommandLearner
  import AmpBridgeWeb.PageWrapper

  @adapter_1 :adapter_1
  @adapter_2 :adapter_2


  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, current_path: "/serial-analysis")

    if connected?(socket) do
      Phoenix.PubSub.subscribe(AmpBridge.PubSub, "serial_data")
    end

    available_devices = AmpBridge.SerialManager.get_available_devices()
    connection_status = AmpBridge.SerialManager.get_connection_status()
    device = AmpBridge.Devices.get_device(1)

    {configured_zones, zone_mute_states, zone_source_states, zone_sources} =
      if device && device.zones && map_size(device.zones) > 0 do
        zones_map = device.zones
        sources_map = device.sources || %{}

        zone_numbers =
          zones_map
          |> Map.keys()
          |> Enum.map(&String.to_integer/1)
          |> Enum.sort()

        mute_states =
          zone_numbers
          |> Enum.map(fn zone -> {zone, false} end)
          |> Enum.into(%{})

        source_states =
          zone_numbers
          |> Enum.map(fn zone -> {zone, "Off"} end)
          |> Enum.into(%{})

        sources_list =
          sources_map
          |> Map.keys()
          |> Enum.sort()
          |> Enum.map(fn key ->
            source_data = Map.get(sources_map, key)
            Map.get(source_data, "name", "Source #{String.to_integer(key) + 1}")
          end)

        zone_sources_map =
          zone_numbers
          |> Enum.map(fn zone ->
            {zone, sources_list}
          end)
          |> Enum.into(%{})

        {zone_numbers, mute_states, source_states, zone_sources_map}
      else
        default_zones = [0, 1, 2, 3, 4, 5, 6, 7]

        mute_states =
          default_zones
          |> Enum.map(fn zone -> {zone, false} end)
          |> Enum.into(%{})

        source_states =
          default_zones
          |> Enum.map(fn zone -> {zone, "Off"} end)
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

        {default_zones, mute_states, source_states, zone_sources}
      end

    default_settings = %{
      baud_rate: 57600,
      data_bits: 8,
      stop_bits: 1,
      parity: :none,
      flow_control: true
    }

    adapter_1_settings =
      if connection_status.adapter_1.settings == %{} do
        default_settings
      else
        connection_status.adapter_1.settings
      end

    adapter_2_settings =
      if connection_status.adapter_2.settings == %{} do
        default_settings
      else
        connection_status.adapter_2.settings
      end

    {:ok,
     assign(socket,
       page_title: "Serial Analysis",
       available_devices: available_devices,
       adapter_1_device: connection_status.adapter_1.device,
       adapter_1_settings: adapter_1_settings,
       adapter_1_original_settings: adapter_1_settings,
       adapter_1_connected: connection_status.adapter_1.connected,
       adapter_1_settings_changed: false,
       adapter_1_data: [],
       adapter_1_decoded: [],
       adapter_2_device: connection_status.adapter_2.device,
       adapter_2_settings: adapter_2_settings,
       adapter_2_original_settings: adapter_2_settings,
       adapter_2_connected: connection_status.adapter_2.connected,
       adapter_2_settings_changed: false,
       adapter_2_data: [],
       adapter_2_decoded: [],
       all_messages: [],
       is_recording: false,
       recording_data: [],
       recordings: [],
       current_recording_name: "",
       show_comparison: false,
       show_advanced_settings: false,
       command_input: "",
       sent_commands: [],
       received_responses: [],
       relay_active: false,
       relay_stats: %{total_relayed: 0, adapter_1_to_2: 0, adapter_2_to_1: 0},
       configured_zones: configured_zones,
       zone_mute_states: zone_mute_states,
       zone_source_states: zone_source_states,
       zone_sources: zone_sources,
       device_config: device,
       rolling_buffer_adapter_1: "",
       rolling_buffer_adapter_2: ""
     )}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, :uri, uri)}
  end

  @impl true
  def handle_event(
        "set_adapter_settings",
        %{"adapter" => adapter} = params,
        socket
      ) do
    settings = Map.drop(params, ["_target", "adapter"])
    adapter_atom = String.to_atom(adapter)

    processed_settings = %{
      baud_rate: String.to_integer(settings["baud_rate"]),
      data_bits: String.to_integer(settings["data_bits"]),
      stop_bits: String.to_integer(settings["stop_bits"]),
      parity: String.to_atom(settings["parity"]),
      flow_control: settings["flow_control"] == "rts_cts"
    }

    case AmpBridge.SerialManager.set_adapter_settings(adapter_atom, processed_settings) do
      :ok ->
        socket =
          case adapter_atom do
            @adapter_1 ->
              original = socket.assigns.adapter_1_original_settings
              settings_changed = processed_settings != original

              Logger.info(
                "Adapter 1 settings check: #{inspect(processed_settings)} != #{inspect(original)} = #{settings_changed}"
              )

              assign(socket,
                adapter_1_settings: processed_settings,
                adapter_1_settings_changed: settings_changed
              )

            @adapter_2 ->
              original = socket.assigns.adapter_2_original_settings
              settings_changed = processed_settings != original

              Logger.info(
                "Adapter 2 settings check: #{inspect(processed_settings)} != #{inspect(original)} = #{settings_changed}"
              )

              assign(socket,
                adapter_2_settings: processed_settings,
                adapter_2_settings_changed: settings_changed
              )
          end

        {:noreply, put_flash(socket, :info, "#{adapter} settings updated")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update #{adapter} settings: #{reason}")}
    end
  end

  @impl true
  def handle_event("connect_adapter", %{"adapter" => adapter, "device" => device}, socket) do
    adapter_atom = String.to_atom(adapter)

    if device == "" do
      {:noreply, socket}
    else
      case AmpBridge.SerialManager.connect_adapter(adapter_atom, device) do
        {:ok, _uart_pid} ->
          socket =
            case adapter_atom do
              @adapter_1 ->
                assign(socket,
                  adapter_1_device: device,
                  adapter_1_connected: true,
                  adapter_1_data: [],
                  adapter_1_decoded: []
                )

              @adapter_2 ->
                assign(socket,
                  adapter_2_device: device,
                  adapter_2_connected: true,
                  adapter_2_data: [],
                  adapter_2_decoded: []
                )
            end

          socket =
            if (adapter_atom == @adapter_1 and socket.assigns.adapter_2_connected) or
                 (adapter_atom == @adapter_2 and socket.assigns.adapter_1_connected) do
              Logger.info("Both adapters connected - auto-starting relay and recording")

              case AmpBridge.SerialRelay.start_relay() do
                :ok ->
                  Logger.info("Auto-started serial relay")
                  assign(socket, relay_active: true)

                _ ->
                  socket
              end
              |> assign(is_recording: true, recording_data: [])
            else
              socket
            end

          {:noreply, put_flash(socket, :info, "#{adapter} connected to #{device}")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to connect #{adapter}: #{reason}")}
      end
    end
  end

  @impl true
  def handle_event("reconnect_adapter", %{"adapter" => adapter, "device" => device}, socket) do
    adapter_atom = String.to_atom(adapter)

    # First disconnect, then reconnect
    case AmpBridge.SerialManager.disconnect_adapter(adapter_atom) do
      :ok ->
        # Small delay to ensure disconnection is complete
        Process.sleep(100)

        case AmpBridge.SerialManager.connect_adapter(adapter_atom, device) do
          {:ok, _uart_pid} ->
            # Update socket assigns
            socket =
              case adapter_atom do
                @adapter_1 ->
                  assign(socket,
                    adapter_1_device: device,
                    adapter_1_connected: true,
                    adapter_1_data: [],
                    adapter_1_decoded: [],
                    adapter_1_original_settings: socket.assigns.adapter_1_settings,
                    adapter_1_settings_changed: false
                  )

                @adapter_2 ->
                  assign(socket,
                    adapter_2_device: device,
                    adapter_2_connected: true,
                    adapter_2_data: [],
                    adapter_2_decoded: [],
                    adapter_2_original_settings: socket.assigns.adapter_2_settings,
                    adapter_2_settings_changed: false
                  )
              end

            {:noreply,
             put_flash(socket, :info, "#{adapter} reconnected to #{device} with new settings")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to reconnect #{adapter}: #{reason}")}
        end

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to disconnect #{adapter} for reconnection: #{reason}")}
    end
  end

  @impl true
  def handle_event("disconnect_adapter", %{"adapter" => adapter}, socket) do
    adapter_atom = String.to_atom(adapter)

    case AmpBridge.SerialManager.disconnect_adapter(adapter_atom) do
      :ok ->
        # Update socket assigns
        socket =
          case adapter_atom do
            @adapter_1 ->
              assign(socket,
                adapter_1_device: nil,
                adapter_1_connected: false,
                adapter_1_data: [],
                adapter_1_decoded: []
              )

            @adapter_2 ->
              assign(socket,
                adapter_2_device: nil,
                adapter_2_connected: false,
                adapter_2_data: [],
                adapter_2_decoded: []
              )
          end

        {:noreply, put_flash(socket, :info, "#{adapter} disconnected")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to disconnect #{adapter}: #{reason}")}
    end
  end

  @impl true
  def handle_event("refresh_devices", _params, socket) do
    available_devices = AmpBridge.SerialManager.get_available_devices()
    {:noreply, assign(socket, available_devices: available_devices)}
  end

  @impl true
  def handle_event("toggle_advanced_settings", _params, socket) do
    {:noreply, assign(socket, show_advanced_settings: !socket.assigns.show_advanced_settings)}
  end

  @impl true
  def handle_event("clear_data", _params, socket) do
    {:noreply,
     assign(socket,
       adapter_1_data: [],
       adapter_1_decoded: [],
       adapter_2_data: [],
       adapter_2_decoded: [],
       all_messages: []
     )}
  end

  @impl true
  def handle_event("clear_messages", _params, socket) do
    {:noreply,
     assign(socket, all_messages: [])
     |> put_flash(:info, "Message log cleared")}
  end

  @impl true
  def handle_event("start_recording", _params, socket) do
    if socket.assigns.adapter_1_connected or socket.assigns.adapter_2_connected do
      {:noreply,
       assign(socket,
         is_recording: true,
         recording_data: [],
         current_recording_name: "Recording #{length(socket.assigns.recordings) + 1}"
       )
       |> put_flash(:info, "Started recording - commands will be captured from both adapters")}
    else
      {:noreply,
       put_flash(socket, :error, "Please connect at least one adapter before recording")}
    end
  end

  @impl true
  def handle_event("stop_recording", _params, socket) do
    if socket.assigns.is_recording do
      # Save the recording
      new_recording = %{
        name: socket.assigns.current_recording_name,
        data: socket.assigns.recording_data,
        timestamp: DateTime.utc_now()
      }

      updated_recordings = socket.assigns.recordings ++ [new_recording]

      {:noreply,
       assign(socket,
         is_recording: false,
         recording_data: [],
         recordings: updated_recordings,
         current_recording_name: ""
       )
       |> put_flash(
         :info,
         "Recording saved: #{new_recording.name} (#{length(new_recording.data)} commands)"
       )}
    else
      {:noreply, put_flash(socket, :error, "No recording in progress")}
    end
  end

  @impl true
  def handle_event("reset_volume", _params, socket) do
    if socket.assigns.is_recording do
      {:noreply,
       assign(socket, recording_data: [])
       |> put_flash(:info, "Recording reset - start volume up from 0 again")}
    else
      {:noreply, put_flash(socket, :error, "No recording in progress")}
    end
  end

  @impl true
  def handle_event("show_comparison", _params, socket) do
    if length(socket.assigns.recordings) >= 2 do
      {:noreply, assign(socket, show_comparison: true)}
    else
      {:noreply, put_flash(socket, :error, "Need at least 2 recordings to compare")}
    end
  end

  @impl true
  def handle_event("hide_comparison", _params, socket) do
    {:noreply, assign(socket, show_comparison: false)}
  end

  @impl true
  def handle_event("clear_recordings", _params, socket) do
    {:noreply,
     assign(socket,
       recordings: [],
       recording_data: [],
       is_recording: false,
       show_comparison: false
     )
     |> put_flash(:info, "All recordings cleared")}
  end

  @impl true
  def handle_event("copy_recordings", _params, socket) do
    # Create a simplified array structure for easy analysis
    recordings_data =
      socket.assigns.recordings
      |> Enum.map(fn recording ->
        %{
          name: recording.name,
          command_count: length(recording.data),
          commands:
            recording.data
            |> Enum.map(fn cmd ->
              %{
                hex: cmd.hex,
                adapter: Map.get(cmd, :adapter),
                adapter_name: Map.get(cmd, :adapter_name),
                adapter_color: Map.get(cmd, :adapter_color)
              }
            end),
          timestamp: recording.timestamp
        }
      end)

    # Convert to JSON for clipboard
    json_data = Jason.encode!(recordings_data, pretty: true)

    # Send to client for console log
    {:noreply,
     socket
     |> put_flash(
       :info,
       "Recording data logged to console! Check browser console and send it to me for analysis."
     )
     |> push_event("log_to_console", %{data: json_data})}
  end

  @impl true
  def handle_event("delete_recording", %{"id" => id}, socket) do
    index = String.to_integer(id)
    updated_recordings = List.delete_at(socket.assigns.recordings, index)

    {:noreply,
     assign(socket, recordings: updated_recordings)
     |> put_flash(:info, "Recording deleted")}
  end

  @impl true
  def handle_event("update_command_input", %{"command_input" => command}, socket) do
    {:noreply, assign(socket, command_input: command)}
  end

  @impl true
  def handle_event("send_command", %{"adapter" => adapter}, socket) do
    adapter_atom = String.to_atom(adapter)
    command = socket.assigns.command_input |> String.trim()

    if command == "" do
      {:noreply, put_flash(socket, :error, "Please enter a command to send")}
    else
      case AmpBridge.SerialManager.send_hex_command(adapter_atom, command) do
        {:ok, binary_data} ->
          sent_command = %{
            command: command,
            hex: AmpBridge.SerialManager.format_hex(binary_data),
            timestamp: DateTime.utc_now(),
            size: byte_size(binary_data),
            adapter: adapter_atom,
            adapter_name: AmpBridge.SerialManager.get_adapter_name(adapter_atom),
            adapter_color: AmpBridge.SerialManager.get_adapter_color(adapter_atom)
          }

          new_sent_commands = [sent_command | socket.assigns.sent_commands] |> Enum.take(50)

          {:noreply,
           assign(socket,
             sent_commands: new_sent_commands,
             command_input: ""
           )
           |> put_flash(:info, "Command sent via #{adapter}: #{command}")}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, "Failed to send command via #{adapter}: #{reason}")}
      end
    end
  end

  @impl true
  def handle_event("clear_commands", _params, socket) do
    {:noreply,
     assign(socket,
       sent_commands: [],
       received_responses: []
     )
     |> put_flash(:info, "Command history cleared")}
  end

  @impl true
  def handle_event("start_relay", _params, socket) do
    case AmpBridge.SerialRelay.start_relay() do
      :ok ->
        {:noreply,
         assign(socket, relay_active: true)
         |> put_flash(:info, "Serial relay started - data will be forwarded between adapters")}

      {:error, :already_active} ->
        {:noreply, put_flash(socket, :error, "Relay is already active")}

      {:error, :adapters_not_connected} ->
        {:noreply, put_flash(socket, :error, "Both adapters must be connected to start relay")}
    end
  end

  @impl true
  def handle_event("stop_relay", _params, socket) do
    case AmpBridge.SerialRelay.stop_relay() do
      :ok ->
        {:noreply,
         assign(socket, relay_active: false)
         |> put_flash(:info, "Serial relay stopped")}
    end
  end

  @impl true
  def handle_event("source_change", %{"zone" => zone, "source" => source}, socket) do
    # UI now sends 0-based zones directly
    zone_num = String.to_integer(zone)

    # Update the source state
    updated_source_states = Map.put(socket.assigns.zone_source_states, zone_num, source)

    # Send source change command to ZoneManager if not "Off"
    if source != "Off" do
      # Extract source index from "Source X" format
      source_index =
        case source do
          "Source " <> num_str -> String.to_integer(num_str) - 1
          _ -> 0
        end

      # Call ZoneManager to change source (convert 0-based zone to 1-based)
      zone_manager_zone = zone_num + 1
      AmpBridge.ZoneManager.change_zone_source(zone_manager_zone, source_index)
    end

    {:noreply, assign(socket, zone_source_states: updated_source_states)}
  end

  @impl true
  def handle_event("send_elan_command", %{"command" => command, "adapter" => _adapter}, socket) do
    # Default device ID
    device_id = 1

    case command do
      "mute_zone_" <> zone_str ->
        # UI now sends 0-based zones directly
        zone_num = String.to_integer(zone_str)

        # Try to use learned command first, fallback to ZoneManager
        case CommandLearner.execute_command(device_id, "mute", zone_num) do
          {:ok, :command_sent} ->
            # Command sent successfully, update UI optimistically
            updated_mute_states = Map.put(socket.assigns.zone_mute_states, zone_num, true)
            command_name = String.replace(command, "_", " ") |> String.upcase()

            {:noreply,
             socket
             |> assign(:zone_mute_states, updated_mute_states)
             |> put_flash(:info, "Sent #{command_name} command (learned)")}

          {:error, _reason} ->
            # Fallback to ZoneManager
            # Convert 0-based zone to 1-based for ZoneManager
            zone_manager_zone = zone_num + 1
            AmpBridge.ZoneManager.mute_zone(zone_manager_zone)
            updated_mute_states = Map.put(socket.assigns.zone_mute_states, zone_num, true)
            command_name = String.replace(command, "_", " ") |> String.upcase()

            {:noreply,
             socket
             |> assign(:zone_mute_states, updated_mute_states)
             |> put_flash(:info, "Sent #{command_name} command (default)")}

          nil ->
            # No learned command, fallback to ZoneManager
            # Convert 0-based zone to 1-based for ZoneManager
            zone_manager_zone = zone_num + 1
            AmpBridge.ZoneManager.mute_zone(zone_manager_zone)
            updated_mute_states = Map.put(socket.assigns.zone_mute_states, zone_num, true)
            command_name = String.replace(command, "_", " ") |> String.upcase()

            {:noreply,
             socket
             |> assign(:zone_mute_states, updated_mute_states)
             |> put_flash(:info, "Sent #{command_name} command (default)")}
        end

      "unmute_zone_" <> zone_str ->
        # UI now sends 0-based zones directly
        zone_num = String.to_integer(zone_str)

        # Try to use learned command first, fallback to ZoneManager
        case CommandLearner.execute_command(device_id, "unmute", zone_num) do
          {:ok, :command_sent} ->
            # Command sent successfully, update UI optimistically
            updated_mute_states = Map.put(socket.assigns.zone_mute_states, zone_num, false)
            command_name = String.replace(command, "_", " ") |> String.upcase()

            {:noreply,
             socket
             |> assign(:zone_mute_states, updated_mute_states)
             |> put_flash(:info, "Sent #{command_name} command (learned)")}

          {:error, _reason} ->
            # Fallback to ZoneManager
            # Convert 0-based zone to 1-based for ZoneManager
            zone_manager_zone = zone_num + 1
            AmpBridge.ZoneManager.unmute_zone(zone_manager_zone)
            updated_mute_states = Map.put(socket.assigns.zone_mute_states, zone_num, false)
            command_name = String.replace(command, "_", " ") |> String.upcase()

            {:noreply,
             socket
             |> assign(:zone_mute_states, updated_mute_states)
             |> put_flash(:info, "Sent #{command_name} command (default)")}

          nil ->
            # No learned command, fallback to ZoneManager
            # Convert 0-based zone to 1-based for ZoneManager
            zone_manager_zone = zone_num + 1
            AmpBridge.ZoneManager.unmute_zone(zone_manager_zone)
            updated_mute_states = Map.put(socket.assigns.zone_mute_states, zone_num, false)
            command_name = String.replace(command, "_", " ") |> String.upcase()

            {:noreply,
             socket
             |> assign(:zone_mute_states, updated_mute_states)
             |> put_flash(:info, "Sent #{command_name} command (default)")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Unknown command: #{command}")}
    end
  end

  @impl true
  def handle_event(
        "send_volume_command",
        %{"command" => command, "zone" => zone, "adapter" => adapter},
        socket
      ) do
    # UI now sends 0-based zones directly
    zone_num = String.to_integer(zone)

    # Convert command to target volume
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
      # Use ZoneManager to handle volume control (convert 0-based zone to 1-based)
      zone_manager_zone = zone_num + 1
      AmpBridge.ZoneManager.set_zone_volume(zone_manager_zone, target_volume)

      volume_percent = "#{target_volume}%"
      command_name = "Zone #{zone} Volume #{volume_percent}"

      # Log the command to console
      log_data = %{
        command: command,
        zone: zone_num,
        volume_percent: volume_percent,
        target_volume: target_volume,
        adapter: adapter,
        timestamp: DateTime.utc_now()
      }

      {:noreply,
       socket
       |> put_flash(:info, "Setting #{command_name} via ZoneManager")
       |> push_event("volume_response_log", log_data)}
    else
      {:noreply, put_flash(socket, :error, "Unknown volume command: #{command}")}
    end
  end

  @impl true
  def handle_event(
        "send_volume_up_down",
        %{"command" => command, "zone" => zone, "adapter" => adapter},
        socket
      ) do
    # UI now sends 0-based zones directly
    zone_num = String.to_integer(zone)
    # Default device ID
    device_id = 1

    # Try to use learned command first, fallback to ZoneManager
    control_type =
      case command do
        "volume_up" -> "volume_up"
        "volume_down" -> "volume_down"
        _ -> nil
      end

    if control_type do
      case CommandLearner.execute_command(device_id, control_type, zone_num) do
        {:ok, :command_sent} ->
          # Command sent successfully
          command_name = "Zone #{zone} Volume #{String.capitalize(control_type)}"

          # Log the command to console
          log_data = %{
            command: command,
            zone: zone_num,
            adapter: adapter,
            timestamp: DateTime.utc_now()
          }

          {:noreply,
           socket
           |> put_flash(:info, "Sent #{command_name} command (learned)")
           |> push_event("volume_response_log", log_data)}

        {:error, _reason} ->
          # Fallback to ZoneManager
          # Convert 0-based zone to 1-based for ZoneManager
          zone_manager_zone = zone_num + 1

          {command_name, result} =
            case command do
              "volume_up" ->
                AmpBridge.ZoneManager.volume_up(zone_manager_zone)
                {"Zone #{zone} Volume Up", :ok}

              "volume_down" ->
                AmpBridge.ZoneManager.volume_down(zone_manager_zone)
                {"Zone #{zone} Volume Down", :ok}
            end

          case result do
            :ok ->
              # Log the command to console
              log_data = %{
                command: command,
                zone: zone_num,
                adapter: adapter,
                timestamp: DateTime.utc_now()
              }

              {:noreply,
               socket
               |> put_flash(:info, "Sent #{command_name} command (default)")
               |> push_event("volume_response_log", log_data)}

            {:error, error_msg} ->
              {:noreply, put_flash(socket, :error, error_msg)}
          end

        nil ->
          # No learned command, fallback to ZoneManager
          # Convert 0-based zone to 1-based for ZoneManager
          zone_manager_zone = zone_num + 1

          {command_name, result} =
            case command do
              "volume_up" ->
                AmpBridge.ZoneManager.volume_up(zone_manager_zone)
                {"Zone #{zone} Volume Up", :ok}

              "volume_down" ->
                AmpBridge.ZoneManager.volume_down(zone_manager_zone)
                {"Zone #{zone} Volume Down", :ok}
            end

          case result do
            :ok ->
              # Log the command to console
              log_data = %{
                command: command,
                zone: zone_num,
                adapter: adapter,
                timestamp: DateTime.utc_now()
              }

              {:noreply,
               socket
               |> put_flash(:info, "Sent #{command_name} command (default)")
               |> push_event("volume_response_log", log_data)}

            {:error, error_msg} ->
              {:noreply, put_flash(socket, :error, error_msg)}
          end
      end
    else
      {:noreply, put_flash(socket, :error, "Unknown volume command: #{command}")}
    end
  end

  @impl true
  def handle_event("volume_slider_change", params, socket) do
    case params do
      %{"zone" => zone, "volume" => volume} ->
        # UI now sends 0-based zones directly
        zone_num = String.to_integer(zone)
        volume_num = String.to_integer(volume)

        # Cancel any existing timer for this zone
        timer_key = "volume_timer_#{zone_num}"

        if Map.has_key?(socket.assigns, String.to_atom(timer_key)) do
          Process.cancel_timer(socket.assigns[String.to_atom(timer_key)])
        end

        # Set a new timer for debouncing
        timer = Process.send_after(self(), {:volume_slider_debounced, zone_num, volume_num}, 333)

        # Update the display immediately
        socket = assign(socket, String.to_atom(timer_key), timer)

        {:noreply,
         socket
         |> push_event("update_volume_display", %{zone: zone, volume: volume})}

      _ ->
        Logger.warning("Unexpected volume slider params: #{inspect(params)}")
        {:noreply, put_flash(socket, :error, "Invalid volume slider parameters")}
    end
  end

  @impl true
  def handle_event("copy_to_console", %{"value" => ""}, socket) do
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
  def handle_event("copy_adapter2_hex_to_console", _params, socket) do
    if length(socket.assigns.all_messages) > 0 do
      # Filter messages from adapter 2 and extract hex values
      adapter2_hex_values =
        socket.assigns.all_messages
        # Show in chronological order
        |> Enum.reverse()
        |> Enum.filter(fn message -> message.adapter == :adapter_2 end)
        |> Enum.map(fn message -> message.hex end)

      if length(adapter2_hex_values) > 0 do
        # Send to client for console log
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Adapter 2 hex values logged to console! Check browser console for hex values."
         )
         |> push_event("copy_adapter2_hex_to_console", %{hex_values: adapter2_hex_values})}
      else
        {:noreply, put_flash(socket, :error, "No messages from Adapter 2 to copy")}
      end
    else
      {:noreply, put_flash(socket, :error, "No messages to copy")}
    end
  end

  @impl true
  def handle_event("copy_adapter1_hex_to_console", _params, socket) do
    if length(socket.assigns.all_messages) > 0 do
      # Filter messages from adapter 1 and extract hex values
      adapter1_hex_values =
        socket.assigns.all_messages
        # Show in chronological order
        |> Enum.reverse()
        |> Enum.filter(fn message -> message.adapter == :adapter_1 end)
        |> Enum.map(fn message -> message.hex end)

      if length(adapter1_hex_values) > 0 do
        # Send to client for console log
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Adapter 1 hex values logged to console! Check browser console for hex values."
         )
         |> push_event("copy_adapter1_hex_to_console", %{hex_values: adapter1_hex_values})}
      else
        {:noreply, put_flash(socket, :error, "No messages from Adapter 1 to copy")}
      end
    else
      {:noreply, put_flash(socket, :error, "No messages to copy")}
    end
  end

  # Handle Info
  @impl true
  def handle_info({:volume_slider_debounced, zone_num, volume_num}, socket) do
    # Default device ID
    device_id = 1

    # Try to use learned command first, fallback to ZoneManager
    case CommandLearner.execute_command(device_id, "set_volume", zone_num,
           volume_level: volume_num
         ) do
      {:ok, :command_sent} ->
        # Command sent successfully
        volume_percent = "#{volume_num}%"
        command_name = "Zone #{zone_num} Volume #{volume_percent}"

        # Log the command to console
        log_data = %{
          command: "volume_slider",
          zone: zone_num,
          volume_percent: volume_percent,
          target_volume: volume_num,
          adapter: "adapter_2",
          timestamp: DateTime.utc_now()
        }

        {:noreply,
         socket
         |> put_flash(:info, "Setting #{command_name} (learned)")
         |> push_event("volume_response_log", log_data)}

      {:error, _reason} ->
        # Fallback to ZoneManager
        # Convert 0-based zone to 1-based for ZoneManager
        zone_manager_zone = zone_num + 1
        AmpBridge.ZoneManager.set_zone_volume(zone_manager_zone, volume_num)

        volume_percent = "#{volume_num}%"
        command_name = "Zone #{zone_num} Volume #{volume_percent}"

        # Log the command to console
        log_data = %{
          command: "volume_slider",
          zone: zone_num,
          volume_percent: volume_percent,
          target_volume: volume_num,
          adapter: "adapter_2",
          timestamp: DateTime.utc_now()
        }

        {:noreply,
         socket
         |> put_flash(:info, "Setting #{command_name} (default)")
         |> push_event("volume_response_log", log_data)}

      nil ->
        # No learned command, fallback to ZoneManager
        # Convert 0-based zone to 1-based for ZoneManager
        zone_manager_zone = zone_num + 1
        AmpBridge.ZoneManager.set_zone_volume(zone_manager_zone, volume_num)

        volume_percent = "#{volume_num}%"
        command_name = "Zone #{zone_num} Volume #{volume_percent}"

        # Log the command to console
        log_data = %{
          command: "volume_slider",
          zone: zone_num,
          volume_percent: volume_percent,
          target_volume: volume_num,
          adapter: "adapter_2",
          timestamp: DateTime.utc_now()
        }

        {:noreply,
         socket
         |> put_flash(:info, "Setting #{command_name} (default)")
         |> push_event("volume_response_log", log_data)}
    end
  end

  @impl true
  def handle_info({:serial_data, data, decoded, adapter_info}, socket) do
    adapter = adapter_info.adapter
    # Default device ID
    device_id = 1

    Logger.info(
      "LiveView: Received serial data from #{adapter}: #{AmpBridge.SerialManager.format_hex(data)}"
    )

    Logger.debug("LiveView: Raw data: #{inspect(data)}")
    Logger.debug("LiveView: Decoded: #{inspect(decoded)}")
    Logger.debug("LiveView: Adapter info: #{inspect(adapter_info)}")

    # Get or create rolling buffer for this adapter
    buffer_key = "rolling_buffer_#{adapter}"
    current_buffer = Map.get(socket.assigns, String.to_atom(buffer_key), "")

    # Update rolling buffer with new data
    new_buffer = AmpBridge.ResponsePatternMatcher.create_rolling_buffer(current_buffer, data)

    # Debug logging
    Logger.info("Serial data received: #{AmpBridge.SerialManager.format_hex(data)}")
    Logger.info("Current buffer length: #{byte_size(current_buffer)}")
    Logger.info("New buffer length: #{byte_size(new_buffer)}")
    Logger.info("New buffer hex: #{AmpBridge.SerialManager.format_hex(new_buffer)}")

    # Try to match against learned and default response patterns using the combined buffer
    case CommandLearner.match_response_pattern(device_id, new_buffer, current_buffer) do
      {:ok,
       %{
         control_type: control_type,
         zone: zone,
         source_index: source_index,
         volume_level: _volume_level,
         pattern_type: pattern_type
       }} ->
        Logger.info("Matched #{pattern_type} response: #{control_type} zone #{zone}")

        # Update UI state based on the matched command (using 0-based zones)
        socket =
          case control_type do
            "mute" ->
              updated_mute_states = Map.put(socket.assigns.zone_mute_states, zone, true)
              assign(socket, :zone_mute_states, updated_mute_states)

            "unmute" ->
              updated_mute_states = Map.put(socket.assigns.zone_mute_states, zone, false)
              assign(socket, :zone_mute_states, updated_mute_states)

            "change_source" when source_index != nil ->
              source_name = "Source #{source_index + 1}"

              updated_source_states =
                Map.put(socket.assigns.zone_source_states, zone, source_name)

              assign(socket, :zone_source_states, updated_source_states)

            _ ->
              socket
          end

        # Update the rolling buffer in socket assigns
        socket = assign(socket, String.to_atom(buffer_key), new_buffer)

        # Continue with normal processing
        process_serial_data(socket, data, decoded, adapter_info, adapter)

      :no_match ->
        # No pattern matched, update rolling buffer and continue with normal processing
        socket = assign(socket, String.to_atom(buffer_key), new_buffer)
        process_serial_data(socket, data, decoded, adapter_info, adapter)
    end
  end

  # Extract the serial data processing logic into a separate function
  defp process_serial_data(socket, data, decoded, adapter_info, adapter) do
    # Add new data to the appropriate adapter's list (keep last 100 entries)
    {new_adapter_data, new_adapter_decoded} =
      case adapter do
        @adapter_1 ->
          new_data = [data | socket.assigns.adapter_1_data] |> Enum.take(100)
          new_decoded = [decoded | socket.assigns.adapter_1_decoded] |> Enum.take(100)
          {new_data, new_decoded}

        @adapter_2 ->
          new_data = [data | socket.assigns.adapter_2_data] |> Enum.take(100)
          new_decoded = [decoded | socket.assigns.adapter_2_decoded] |> Enum.take(100)
          {new_data, new_decoded}
      end

    # Add to combined messages with adapter info
    new_message = %{
      timestamp: DateTime.utc_now(),
      hex: AmpBridge.SerialManager.format_hex(data),
      size: byte_size(data),
      decoded: decoded,
      adapter: adapter,
      adapter_name: adapter_info.adapter_name,
      adapter_color: adapter_info.adapter_color
    }

    new_all_messages = [new_message | socket.assigns.all_messages] |> Enum.take(200)

    # If recording, add to recording data
    new_recording_data =
      if socket.assigns.is_recording do
        [Map.merge(decoded, adapter_info) | socket.assigns.recording_data]
      else
        socket.assigns.recording_data
      end

    # Add responses to received_responses for command testing
    new_received_responses =
      [
        %{
          timestamp: DateTime.utc_now(),
          hex: AmpBridge.SerialManager.format_hex(data),
          size: byte_size(data),
          decoded: decoded,
          adapter: adapter,
          adapter_name: adapter_info.adapter_name,
          adapter_color: adapter_info.adapter_color
        }
        | socket.assigns.received_responses
      ]
      |> Enum.take(50)

    # Update socket assigns based on adapter
    socket =
      case adapter do
        @adapter_1 ->
          assign(socket,
            adapter_1_data: new_adapter_data,
            adapter_1_decoded: new_adapter_decoded,
            all_messages: new_all_messages,
            recording_data: new_recording_data,
            received_responses: new_received_responses
          )

        @adapter_2 ->
          assign(socket,
            adapter_2_data: new_adapter_data,
            adapter_2_decoded: new_adapter_decoded,
            all_messages: new_all_messages,
            recording_data: new_recording_data,
            received_responses: new_received_responses
          )
      end

    {:noreply, socket}
  end
end
