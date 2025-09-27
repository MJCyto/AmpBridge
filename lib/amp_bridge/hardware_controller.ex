defmodule AmpBridge.HardwareController do
  @moduledoc """
  Hardware Controller - Manages a specific amplifier and sends serial commands based on device updates.

  Each controller:
  - Subscribes to PubSub updates for its assigned device
  - Translates volume/setting changes into serial commands
  - Manages the serial connection to the amplifier
  - Handles command queuing and error recovery

  Serial Command Examples:
  - Volume: "VOL001" (set volume to 1%)
  - Mute: "MUT1" (mute on)
  - Power: "PWR1" (power on)
  - Source: "SRC1" (select input 1)
  """

  use GenServer
  require Logger

  # Client API

  @doc """
  Starts a hardware controller for a specific amplifier.
  """
  def start_link(opts) do
    device_id = opts.device_id
    name = opts.name

    Logger.info("Starting Hardware Controller for #{name} (Device #{device_id})")

    GenServer.start_link(__MODULE__, opts,
      name: {:via, Registry, {AmpBridge.Registry, {__MODULE__, device_id}}}
    )
  end

  @doc """
  Sends a command to the amplifier.
  """
  def send_command(controller_pid, command_type, params) do
    GenServer.call(controller_pid, {:send_command, command_type, params})
  end

  @doc """
  Gets the current status of the amplifier.
  """
  def get_status(controller_pid) do
    GenServer.call(controller_pid, :get_status)
  end

  @doc """
  Gets information about this controller.
  """
  def get_info(controller_pid) do
    GenServer.call(controller_pid, :get_info)
  end

  @doc """
  Checks if this controller manages a specific device.
  """
  def is_device(controller_pid, device_id) do
    GenServer.call(controller_pid, {:is_device, device_id})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    device_id = opts.device_id
    name = opts.name

    # Get the assigned USB device for this amplifier
    assigned_device = AmpBridge.USBDeviceScanner.get_amp_device_assignment(device_id)

    serial_config = %{
      port: assigned_device || Map.get(opts, :serial_port),
      baud_rate: opts.baud_rate || 9600,
      data_bits: opts.data_bits || 8,
      stop_bits: opts.stop_bits || 1,
      parity: opts.parity || :none
    }

    Logger.info("Hardware Controller #{name} initializing for device #{device_id}")

    if serial_config.port do
      Logger.info("Using serial port: #{serial_config.port}")
    else
      Logger.info("No serial port assigned - will use mock serial until USB device is assigned")
    end

    # Subscribe to device updates for this specific device
    Phoenix.PubSub.subscribe(AmpBridge.PubSub, "device_updates")

    # Initialize state
    state = %{
      device_id: device_id,
      name: name,
      serial_config: serial_config,
      serial_connection: nil,
      last_known_state: %{},
      command_queue: [],
      is_connected: false,
      error_count: 0,
      last_error: nil,
      assigned_usb_device: assigned_device
    }

    # Start the serial connection process
    serial_pid = start_serial_connection(serial_config)

    state = %{state | serial_connection: serial_pid}

    Logger.info("Hardware Controller #{name} initialized successfully")
    {:ok, state}
  end

  @impl true
  def handle_info({:device_updated, updated_device}, state) do
    # Only process updates for our assigned device
    if updated_device.id == state.device_id do
      Logger.info(
        "Hardware Controller #{state.name}: Received update for device #{state.device_id}"
      )

      # Update last known state
      state = %{
        state
        | last_known_state: updated_device
      }

      # Note: Device updates from MQTT are handled by MQTT client
      # This handler is for UI-generated updates that need HardwareController processing
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:zone_volume_changed, zone_id, volume}, state) do
    Logger.debug("Hardware Controller #{state.name}: Zone #{zone_id} volume changed to #{volume}%")
    {:noreply, state}
  end

  @impl true
  def handle_info({:zone_source_changed, zone_id, source_name}, state) do
    Logger.info("Hardware Controller #{state.name}: Zone #{zone_id} source changed to #{source_name}")

    # Use CommandLearner system like MQTT client does
    case source_name do
      "Off" ->
        Logger.info("Sending turn_off command for zone #{zone_id} using device #{state.device_id}")
        case AmpBridge.CommandLearner.execute_command(state.device_id, "turn_off", zone_id) do
          {:ok, :command_sent} ->
            Logger.info("Turn off command sent successfully for zone #{zone_id}")
          {:error, reason} ->
            Logger.warning("Failed to send turn off command for zone #{zone_id}: #{reason}")
        end
      source_name when is_binary(source_name) ->
        # Extract index from "Source X" format (1-based to 0-based)
        case Regex.run(~r/Source (\d+)/, source_name) do
          [_, index_str] ->
            source_index = String.to_integer(index_str) - 1
            Logger.info("Sending change_source command for zone #{zone_id} to source #{source_index}")
            case AmpBridge.CommandLearner.execute_command(state.device_id, "change_source", zone_id, source_index: source_index) do
              {:ok, :command_sent} ->
                Logger.info("Change source command sent successfully for zone #{zone_id}")
              {:error, reason} ->
                Logger.warning("Failed to send change source command for zone #{zone_id}: #{reason}")
            end
          nil ->
            Logger.warning("Could not parse source name: #{source_name}")
        end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:device_deleted, device_id}, state) do
    if device_id == state.device_id do
      Logger.warning(
        "Hardware Controller #{state.name}: Device #{device_id} was deleted, shutting down"
      )

      {:stop, :device_deleted, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:circuits_uart, _port, {:error, reason}}, state) do
    Logger.error("Hardware Controller #{state.name}: Serial error: #{reason}")
    state = %{state | error_count: state.error_count + 1, last_error: reason}
    {:noreply, state}
  end

  @impl true
  def handle_info({:circuits_uart, _port, data}, state) do
    Logger.info("Hardware Controller #{state.name}: Received serial data: #{inspect(data)}")
    # Process incoming serial data here if needed
    {:noreply, state}
  end

  @impl true
  def handle_call({:send_command, command_type, params}, _from, state) do
    command = build_command(command_type, params)
    result = send_serial_command(state.serial_connection, command)

    case result do
      {:ok, response} ->
        Logger.info("Hardware Controller #{state.name}: Command '#{command}' sent successfully")
        {:reply, {:ok, response}, state}

      {:error, reason} ->
        Logger.error(
          "Hardware Controller #{state.name}: Failed to send command '#{command}': #{reason}"
        )

        state = %{state | error_count: state.error_count + 1, last_error: reason}
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      device_id: state.device_id,
      name: state.name,
      is_connected: state.is_connected,
      error_count: state.error_count,
      last_error: state.last_error,
      command_queue_length: length(state.command_queue),
      last_known_state: state.last_known_state
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    info = %{
      device_id: state.device_id,
      name: state.name,
      serial_port: state.serial_config.port,
      is_connected: state.is_connected
    }

    {:reply, info, state}
  end

  @impl true
  def handle_call({:is_device, device_id}, _from, state) do
    {:reply, device_id == state.device_id, state}
  end

  # Private functions

  defp start_serial_connection(config) do
    if config.port do
      Logger.info("Starting serial connection to #{config.port}")

      case Circuits.UART.start_link() do
        {:ok, uart} ->
          case Circuits.UART.open(uart, config.port,
                 speed: config.baud_rate,
                 data_bits: config.data_bits,
                 stop_bits: config.stop_bits,
                 parity: config.parity,
                 active: true
               ) do
            :ok ->
              Logger.info("Serial connection established to #{config.port}")
              uart

            {:error, reason} ->
              Logger.error("Failed to open serial port #{config.port}: #{reason}")
              # Fall back to mock process if serial connection fails
              spawn_link(fn -> mock_serial_process() end)
          end

        {:error, reason} ->
          Logger.error("Failed to start UART: #{reason}")
          # Fall back to mock process
          spawn_link(fn -> mock_serial_process() end)
      end
    else
      Logger.info("No serial port assigned - starting mock serial process")
      spawn_link(fn -> mock_serial_process() end)
    end
  end

  defp mock_serial_process do
    receive do
      {:send_command, command} ->
        Logger.info("Mock Serial: Sending command '#{command}'")
        # Simulate some processing time
        Process.sleep(50)
        # Simulate success/failure
        if :rand.uniform() > 0.1 do
          Logger.info("Mock Serial: Command successful")
        else
          Logger.error("Mock Serial: Command failed (simulated)")
        end

        mock_serial_process()

      _ ->
        mock_serial_process()
    end
  end

  defp generate_commands(old_state, new_state) do
    commands = []

    # Volume changes removed - no master volume

    # Check for device master volume changes
    old_device_master =
      if is_map(old_state) && Map.has_key?(old_state, :settings) do
        get_in(old_state.settings, ["device_master_volume"])
      else
        nil
      end

    new_device_master = get_in(new_state.settings, ["device_master_volume"])

    commands =
      if old_device_master != new_device_master do
        [%{type: :device_master_volume, value: new_device_master} | commands]
      else
        commands
      end

    # Check for output volume changes
    commands =
      if is_map(old_state) && Map.has_key?(old_state, :outputs) && old_state.outputs &&
           new_state.outputs do
        Enum.reduce(Enum.with_index(new_state.outputs), commands, fn {output, index}, acc ->
          old_output = Enum.at(old_state.outputs, index)

          if old_output && old_output.volume != output.volume do
            [%{type: :output_volume, output_index: index, value: output.volume} | acc]
          else
            acc
          end
        end)
      else
        commands
      end

    # Check for zone changes
    commands =
      if is_map(old_state) && Map.has_key?(old_state, :zones) && old_state.zones &&
           new_state.zones do
        Enum.reduce(new_state.zones, commands, fn {zone_id, zone}, acc ->
          old_zone = Map.get(old_state.zones, zone_id)

          zone_commands = []

          # Check zone volume changes
          zone_commands =
            if old_zone && old_zone["master_volume"] != zone["master_volume"] do
              [
                %{type: :zone_volume, zone_id: zone_id, value: zone["master_volume"]}
                | zone_commands
              ]
            else
              zone_commands
            end

          # Check zone power changes
          zone_commands =
            if old_zone && old_zone["power"] != zone["power"] do
              [%{type: :zone_power, zone_id: zone_id, value: zone["power"]} | zone_commands]
            else
              zone_commands
            end

          # Check zone mute changes
          zone_commands =
            if old_zone && old_zone["mute"] != zone["mute"] do
              [%{type: :zone_mute, zone_id: zone_id, value: zone["mute"]} | zone_commands]
            else
              zone_commands
            end

          # Check zone output assignments
          zone_commands =
            if old_zone && old_zone["output_ids"] != zone["output_ids"] do
              [
                %{type: :zone_outputs, zone_id: zone_id, output_ids: zone["output_ids"]}
                | zone_commands
              ]
            else
              zone_commands
            end

          zone_commands ++ acc
        end)
      else
        commands
      end

    # Check for speaker group changes
    commands =
      if is_map(old_state) && Map.has_key?(old_state, :speaker_groups) && old_state.speaker_groups &&
           new_state.speaker_groups do
        Enum.reduce(new_state.speaker_groups, commands, fn {group_id, group}, acc ->
          old_group = Map.get(old_state.speaker_groups, group_id)

          group_commands = []

          # Check group volume changes
          group_commands =
            if old_group && old_group["master_volume"] != group["master_volume"] do
              [
                %{type: :group_volume, group_id: group_id, value: group["master_volume"]}
                | group_commands
              ]
            else
              group_commands
            end

          # Check group power changes
          group_commands =
            if old_group && old_group["power"] != group["power"] do
              [
                %{type: :group_power, group_id: group_id, value: group["power"]}
                | group_commands
              ]
            else
              group_commands
            end

          # Check group mute changes
          group_commands =
            if old_group && old_group["mute"] != group["mute"] do
              [%{type: :group_mute, group_id: group_id, value: group["mute"]} | group_commands]
            else
              group_commands
            end

          # Check group zone assignments
          group_commands =
            if old_group && old_group["zone_ids"] != group["zone_ids"] do
              [
                %{type: :group_zones, group_id: group_id, zone_ids: group["zone_ids"]}
                | group_commands
              ]
            else
              group_commands
            end

          group_commands ++ acc
        end)
      else
        commands
      end

    commands
  end

  defp build_command(:master_volume, %{value: value}) do
    # Example: "VOL001" for 1%, "VOL100" for 100%
    "VOL#{String.pad_leading("#{value}", 3, "0")}"
  end

  defp build_command(:device_master_volume, %{value: value}) do
    "DMV#{String.pad_leading("#{value}", 3, "0")}"
  end

  defp build_command(:output_volume, %{output_index: index, value: value}) do
    "OUT#{index}#{String.pad_leading("#{value}", 3, "0")}"
  end

  defp build_command(:mute, %{output_index: index, value: muted}) do
    "MUT#{index}#{if muted, do: "1", else: "0"}"
  end

  defp build_command(:power, %{output_index: index, value: powered}) do
    "PWR#{index}#{if powered, do: "1", else: "0"}"
  end

  # Zone commands
  defp build_command(:zone_volume, %{zone_id: zone_id, value: value}) do
    "ZON#{zone_id}VOL#{String.pad_leading("#{value}", 3, "0")}"
  end

  defp build_command(:zone_power, %{zone_id: zone_id, value: powered}) do
    "ZON#{zone_id}PWR#{if powered, do: "1", else: "0"}"
  end

  defp build_command(:zone_mute, %{zone_id: zone_id, value: muted}) do
    "ZON#{zone_id}MUT#{if muted, do: "1", else: "0"}"
  end

  defp build_command(:zone_outputs, %{zone_id: zone_id, output_ids: output_ids}) do
    # Send output assignments for the zone
    # Format: "ZON{zone_id}OUT{output_ids}"
    output_list = Enum.join(output_ids, ",")
    "ZON#{zone_id}OUT#{output_list}"
  end

  defp build_command(:zone_source, %{zone_id: zone_id, source_name: source_name}) do
    # Parse source name to get source index
    case source_name do
      "Off" ->
        "ZON#{zone_id}SRCOFF"

      source_name when is_binary(source_name) ->
        # Extract index from "Source X" format (1-based to 0-based)
        case Regex.run(~r/Source (\d+)/, source_name) do
          [_, index_str] ->
            source_index = String.to_integer(index_str) - 1
            Logger.info("Hardware Controller: Converting '#{source_name}' to source index #{source_index}")
            "ZON#{zone_id}SRC#{source_index}"
          nil ->
            # Try to parse as direct source name (like "Echo", "Server", etc.)
            # Map common source names to indices
            source_index = case source_name do
              "Echo" -> 0
              "Server" -> 1
              "Source 3" -> 2
              "Source 4" -> 3
              "Source 5" -> 4
              "Source 6" -> 5
              "Source 7" -> 6
              "Source 8" -> 7
              _ ->
                Logger.warning("Could not parse source name: #{source_name}")
                0  # Default to source 0
            end
            Logger.info("Hardware Controller: Converting '#{source_name}' to source index #{source_index}")
            "ZON#{zone_id}SRC#{source_index}"
        end

      _ ->
        Logger.warning("Invalid source name format: #{inspect(source_name)}")
        "ZON#{zone_id}SRC0"  # Default to source 0
    end
  end

  # Speaker Group commands
  defp build_command(:group_volume, %{group_id: group_id, value: value}) do
    "GRP#{group_id}VOL#{String.pad_leading("#{value}", 3, "0")}"
  end

  defp build_command(:group_power, %{group_id: group_id, value: powered}) do
    "GRP#{group_id}PWR#{if powered, do: "1", else: "0"}"
  end

  defp build_command(:group_mute, %{group_id: group_id, value: muted}) do
    "GRP#{group_id}MUT#{if muted, do: "1", else: "0"}"
  end

  defp build_command(:group_zones, %{group_id: group_id, zone_ids: zone_ids}) do
    # Send zone assignments for the group
    # Format: "GRP{group_id}ZON{zone_ids}"
    zone_list = Enum.join(zone_ids, ",")
    "GRP#{group_id}ZON#{zone_list}"
  end

  defp send_serial_command(uart, command) when is_pid(uart) do
    # Try to use it as a UART first
    case Circuits.UART.write(uart, command) do
      :ok ->
        {:ok, "OK"}

      {:error, _reason} ->
        # If UART write fails, treat it as a mock process
        send(uart, {:send_command, command})
        {:ok, "OK"}
    end
  end

  defp process_command_queue(state) do
    case state.command_queue do
      [] ->
        state

      [command | rest] ->
        Logger.info("Hardware Controller #{state.name}: Processing command #{inspect(command)}")

        # Use CommandLearner system for command processing
        case process_command_with_learner(command, state.device_id) do
          :ok ->
            %{state | command_queue: rest}
          {:error, reason} ->
            Logger.error(
              "Hardware Controller #{state.name}: Command failed, will retry: #{reason}"
            )
            # Keep the command in the queue for retry
            state
        end
    end
  end

  defp process_command_with_learner(command, device_id) do
    case command.type do
      :zone_source ->
        case command.source_name do
          "Off" ->
            case AmpBridge.CommandLearner.execute_command(device_id, "turn_off", command.zone_id) do
              {:ok, :command_sent} -> :ok
              {:error, reason} -> {:error, reason}
            end
          source_name when is_binary(source_name) ->
            case Regex.run(~r/Source (\d+)/, source_name) do
              [_, index_str] ->
                source_index = String.to_integer(index_str) - 1
                case AmpBridge.CommandLearner.execute_command(device_id, "change_source", command.zone_id, source_index: source_index) do
                  {:ok, :command_sent} -> :ok
                  {:error, reason} -> {:error, reason}
                end
              nil ->
                {:error, "Could not parse source name: #{source_name}"}
            end
        end
      _ ->
        {:error, "Unsupported command type: #{command.type}"}
    end
  end
end
