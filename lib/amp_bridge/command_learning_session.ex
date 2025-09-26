defmodule AmpBridge.CommandLearningSession do
  @moduledoc """
  GenServer that handles command learning sessions.

  This process:
  1. Listens for serial data from both controller and amp
  2. Collects all hex messages during the learning period
  3. Uses a timer to detect when learning is complete (0.5s silence)
  4. Stores the learned command with both controller and amp data
  """

  use GenServer
  require Logger

  # Client API

  def start_link(device_id, control_type, zone, opts) do
    GenServer.start_link(__MODULE__, {device_id, control_type, zone, opts},
      name: via_tuple(device_id)
    )
  end

  def add_data(device_id, data, adapter) do
    Logger.info("CommandLearningSession: Adding data for device #{device_id}, adapter #{adapter}")

    # Check if the session exists in the registry
    case Registry.lookup(AmpBridge.CommandLearningRegistry, device_id) do
      [{_pid, _value}] ->
        Logger.info("CommandLearningSession: Session found for device #{device_id}")

        try do
          GenServer.cast(via_tuple(device_id), {:add_data, data, adapter})
        rescue
          error ->
            Logger.warning("Failed to add data to learning session: #{inspect(error)}")
        end

      [] ->
        Logger.warning("CommandLearningSession: No active session found for device #{device_id}")
    end
  end

  def stop_learning(device_id) do
    GenServer.cast(via_tuple(device_id), :stop_learning)
  end

  def get_status(device_id) do
    GenServer.call(via_tuple(device_id), :get_status)
  end

  # Server callbacks

  def init({device_id, control_type, zone, opts}) do
    # Get device configuration to determine adapter roles
    device = AmpBridge.Devices.get_device(device_id)

    state = %{
      device_id: device_id,
      control_type: control_type,
      zone: zone,
      opts: opts,
      controller_data: [],
      amp_data: [],
      last_data_time: nil,
      timer_ref: nil,
      status: :listening,
      adapter_1_role: device && device.adapter_1_role,
      adapter_2_role: device && device.adapter_2_role
    }

    Logger.info("Command learning session started for #{control_type} zone #{zone}")
    Logger.info("Adapter roles - 1: #{state.adapter_1_role}, 2: #{state.adapter_2_role}")
    {:ok, state}
  end

  def handle_cast({:add_data, data, adapter}, state) do
    Logger.info("Received data from #{adapter}: #{AmpBridge.SerialManager.format_hex(data)}")
    Logger.info("Adapter roles - 1: #{state.adapter_1_role}, 2: #{state.adapter_2_role}")

    # Add data to appropriate collection based on adapter roles
    new_state =
      case {adapter, state.adapter_1_role, state.adapter_2_role} do
        {:adapter_1, "controller", _} ->
          Logger.info("Mapping adapter_1 data to controller_data")
          %{state | controller_data: state.controller_data ++ [data]}

        {:adapter_1, "amp", _} ->
          Logger.info("Mapping adapter_1 data to amp_data")
          %{state | amp_data: state.amp_data ++ [data]}

        {:adapter_2, _, "controller"} ->
          Logger.info("Mapping adapter_2 data to controller_data")
          %{state | controller_data: state.controller_data ++ [data]}

        {:adapter_2, _, "amp"} ->
          Logger.info("Mapping adapter_2 data to amp_data")
          %{state | amp_data: state.amp_data ++ [data]}

        _ ->
          Logger.warning(
            "Unknown adapter role mapping: adapter=#{adapter}, adapter_1_role=#{state.adapter_1_role}, adapter_2_role=#{state.adapter_2_role}"
          )

          state
      end

    # Update last data time and reset timer
    new_state = %{new_state | last_data_time: System.monotonic_time(:millisecond)}

    # Log current data counts
    Logger.info(
      "Data counts - Controller: #{length(new_state.controller_data)}, Amp: #{length(new_state.amp_data)}"
    )

    # Cancel existing timer and start new one
    if new_state.timer_ref do
      Process.cancel_timer(new_state.timer_ref)
    end

    timer_ref = Process.send_after(self(), :learning_timeout, 2000)
    new_state = %{new_state | timer_ref: timer_ref}

    {:noreply, new_state}
  end

  def handle_cast(:stop_learning, state) do
    Logger.info("Stopping command learning session")
    {:stop, :normal, state}
  end

  def handle_info(:learning_timeout, state) do
    Logger.info("Learning timeout reached, finalizing command")
    Logger.info("Controller data count: #{length(state.controller_data)}")
    Logger.info("Amp data count: #{length(state.amp_data)}")

    # Combine all data into single binaries
    controller_sequence = combine_data(state.controller_data)
    amp_sequence = combine_data(state.amp_data)

    Logger.info("Controller sequence: #{AmpBridge.SerialManager.format_hex(controller_sequence)}")
    Logger.info("Amp sequence: #{AmpBridge.SerialManager.format_hex(amp_sequence)}")

    # Validate that we have controller data
    if byte_size(controller_sequence) == 0 do
      Logger.error("No controller data received - command learning failed")
      {:stop, :error, %{state | status: :error}}
    else
      # Convert controller data to hex array format for serial_commands table
      hex_array_json = flatten_to_hex_array(state.controller_data)

      # Store the learned command in serial_commands table
      case store_learned_command_in_serial_commands(state, hex_array_json) do
        {:ok, _serial_command} ->
          Logger.info("Successfully learned command for #{state.control_type} zone #{state.zone}")

          # Notify the LiveView that a command was learned
          Phoenix.PubSub.broadcast(
            AmpBridge.PubSub,
            "command_learned",
            {:command_learned, state.device_id, state.control_type, state.zone}
          )

          {:stop, :normal, %{state | status: :completed}}

        {:error, reason} ->
          Logger.error("Failed to store learned command: #{inspect(reason)}")
          {:stop, :error, %{state | status: :error}}
      end
    end
  end

  def handle_call(:get_status, _from, state) do
    {:reply, state.status, state}
  end

  # Private functions

  defp store_learned_command_in_serial_commands(state, hex_array_json) do
    alias AmpBridge.HexCommandManager
    alias AmpBridge.LearnedCommands

    # Convert JSON back to hex values
    case Jason.decode(hex_array_json) do
      {:ok, base64_array} ->
        hex_values = Enum.map(base64_array, fn base64_binary ->
          case Base.decode64(base64_binary) do
            {:ok, binary} -> :binary.bin_to_list(binary) |> hd()
            {:error, _} -> 0
          end
        end)

        case state.control_type do
          "mute" ->
            HexCommandManager.update_command(state.zone, :mute, hex_values)
          "unmute" ->
            HexCommandManager.update_command(state.zone, :unmute, hex_values)
          _ ->
            # For other control types, store in learned_commands table
            Logger.info("Storing #{state.control_type} command in learned_commands table")
            store_in_learned_commands_table(state, hex_values)
        end
      {:error, _} ->
        {:error, :invalid_json}
    end
  end

  defp store_in_learned_commands_table(state, hex_values) do
    alias AmpBridge.LearnedCommands

    # Convert hex values back to binary for learned_commands table
    command_sequence = :binary.list_to_bin(hex_values)

    # For now, we don't have amp response data in this flow, so use empty binary
    response_pattern = <<>>

    attrs = %{
      device_id: state.device_id,
      control_type: state.control_type,
      zone: state.zone,
      command_sequence: command_sequence,
      response_pattern: response_pattern,
      learned_at: NaiveDateTime.utc_now()
    }

    # Add optional fields
    attrs = if source_index = Keyword.get(state.opts, :source_index) do
      Map.put(attrs, :source_index, source_index)
    else
      attrs
    end

    attrs = if volume_level = Keyword.get(state.opts, :volume_level) do
      Map.put(attrs, :volume_level, volume_level)
    else
      attrs
    end

    # Check if a command already exists for this device, control_type, zone, and options
    existing_command = LearnedCommands.get_command(state.device_id, state.control_type, state.zone, state.opts)

    case existing_command do
      nil ->
        # No existing command, create a new one
        case LearnedCommands.create_command(attrs) do
          {:ok, learned_command} ->
            Logger.info("Successfully created new #{state.control_type} command in learned_commands table")
            {:ok, learned_command}
          {:error, changeset} ->
            Logger.error("Failed to create command in learned_commands: #{inspect(changeset.errors)}")
            {:error, changeset}
        end
      existing ->
        # Command exists, update it instead of creating a duplicate
        Logger.info("Command already exists, updating existing #{state.control_type} command (ID: #{existing.id})")
        case LearnedCommands.update_command(existing, attrs) do
          {:ok, learned_command} ->
            Logger.info("Successfully updated #{state.control_type} command in learned_commands table")
            {:ok, learned_command}
          {:error, changeset} ->
            Logger.error("Failed to update command in learned_commands: #{inspect(changeset.errors)}")
            {:error, changeset}
        end
    end
  end

  defp via_tuple(device_id) do
    {:via, Registry, {AmpBridge.CommandLearningRegistry, device_id}}
  end

  defp combine_data(data_list) do
    data_list
    |> Enum.join()
    |> :binary.bin_to_list()
    |> :binary.list_to_bin()
  end

  defp flatten_to_hex_array(data_list) do
    data_list
    |> Enum.join()
    |> :binary.bin_to_list()
    |> Enum.map(fn byte -> <<byte>> end)
    |> Enum.map(&Base.encode64/1)
    |> Jason.encode!()
  end
end
