defmodule AmpBridge.CommandLearner do
  @moduledoc """
  Module for learning and managing amplifier commands.

  Handles the process of learning command sequences and response patterns
  during the command learning phase of system initialization.
  """

  require Logger
  alias AmpBridge.LearnedCommands
  alias AmpBridge.LearnedCommand
  alias AmpBridge.SerialManager
  alias AmpBridge.CommandLearningSession
  alias AmpBridge.ResponsePatternMatcher

  @doc """
  Execute a command using learned commands if available, otherwise return nil.

  This is used by the serial analysis page to test commands without starting learning mode.
  """
  def execute_command(_device_id, control_type, zone, opts \\ []) do
    Logger.info("Executing command: #{control_type} for zone #{zone} with opts #{inspect(opts)}")

    # Use HexCommandManager to get commands from serial_commands table
    case get_command_from_serial_commands(control_type, zone, opts) do
      {:ok, hex_chunks} ->
        Logger.info("Using learned command for #{control_type} zone #{zone}")

        case send_hex_chunks(hex_chunks) do
          :ok ->
            {:ok, :command_sent}

          {:error, reason} ->
            Logger.error("Failed to send learned command: #{reason}")
            {:error, reason}
        end

      {:error, :no_command} ->
        Logger.info(
          "No learned command for #{control_type} zone #{zone}, returning nil for fallback"
        )

        nil

      {:error, reason} ->
        Logger.error("Failed to get command: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Start learning a command for a specific control action.

  This should be called when a user clicks a control in our UI during command learning.
  It will:
  1. Check if we already have a learned command (if so, use it)
  2. If not, start listening mode for capturing commands from manufacturer's app
  3. User then goes to manufacturer's app and clicks the same control
  4. We capture all hex messages from both controller and amp
  5. After 0.5s of silence, we stop recording and store the learned command
  """
  def learn_command(device_id, control_type, zone, opts \\ []) do
    Logger.info("Learning command: #{control_type} for zone #{zone} with opts #{inspect(opts)}")

    # First check if we already have a learned command
    case LearnedCommands.get_command(device_id, control_type, zone, opts) do
      %LearnedCommand{command_sequence: command_sequence} ->
        Logger.info("Using learned command for #{control_type} zone #{zone}")

        case send_command(command_sequence) do
          :ok ->
            {:ok, :command_sent}

          {:error, reason} ->
            Logger.error("Failed to send learned command: #{reason}")
            {:error, reason}
        end

      nil ->
        Logger.info(
          "No learned command for #{control_type} zone #{zone}, starting learning mode."
        )

        # Start learning mode - listen for commands from manufacturer's app
        start_command_learning(device_id, control_type, zone, opts)
    end
  end

  @doc """
  Record a learned command with its response pattern.

  This is called when we've observed a command being sent and its response.
  """
  def record_learned_command(
        device_id,
        control_type,
        zone,
        command_sequence,
        response_pattern,
        opts \\ []
      ) do
    attrs = %{
      device_id: device_id,
      control_type: control_type,
      zone: zone,
      command_sequence: command_sequence,
      response_pattern: response_pattern,
      learned_at: NaiveDateTime.utc_now()
    }

    # Add optional fields
    attrs =
      if source_index = Keyword.get(opts, :source_index) do
        Map.put(attrs, :source_index, source_index)
      else
        attrs
      end

    attrs =
      if volume_level = Keyword.get(opts, :volume_level) do
        Map.put(attrs, :volume_level, volume_level)
      else
        attrs
      end

    case LearnedCommands.create_command(attrs) do
      {:ok, learned_command} ->
        Logger.info("Recorded learned command: #{control_type} for zone #{zone}")
        {:ok, learned_command}

      {:error, changeset} ->
        Logger.error("Failed to record learned command: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Match incoming serial data against learned and default response patterns.

  This is called when we receive serial data to see if it matches
  any response patterns and update the UI accordingly.
  """
  def match_response_pattern(device_id, serial_data, rolling_buffer \\ "") do
    # Use the new ResponsePatternMatcher which handles both learned and default patterns
    ResponsePatternMatcher.match_response(device_id, serial_data, rolling_buffer)
  end

  @doc """
  Get the current learning status for a device.
  """
  def get_learning_status(device_id) do
    commands = LearnedCommands.list_commands_for_device(device_id)

    # Group commands by type
    mute_commands = Enum.filter(commands, &(&1.control_type in ["mute", "unmute"]))

    volume_commands =
      Enum.filter(commands, &(&1.control_type in ["volume_up", "volume_down", "set_volume"]))

    source_commands = Enum.filter(commands, &(&1.control_type == "change_source"))

    %{
      total_commands: length(commands),
      mute_commands: length(mute_commands),
      volume_commands: length(volume_commands),
      source_commands: length(source_commands),
      commands_by_zone: group_commands_by_zone(commands)
    }
  end

  @doc """
  Check if command learning is complete for a device.
  """
  def learning_complete?(device_id) do
    # This would check if all necessary commands have been learned
    # For now, just check if we have any learned commands
    commands = LearnedCommands.list_commands_for_device(device_id)
    length(commands) > 0
  end

  @doc """
  Start command learning mode for a specific control.

  This starts listening for hex messages from both controller and amp.
  The user should then go to the manufacturer's app and click the same control.
  """
  def start_command_learning(device_id, control_type, zone, opts) do
    Logger.info("Starting command learning for #{control_type} zone #{zone}")

    # Start a GenServer process to handle the learning session
    case CommandLearningSession.start_link(device_id, control_type, zone, opts) do
      {:ok, pid} ->
        Logger.info("Command learning session started with PID: #{inspect(pid)}")
        {:ok, :learning_started, pid}

      {:error, reason} ->
        Logger.error("Failed to start command learning: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Process incoming serial data during command learning.

  This is called by the SerialManager when we receive data during learning mode.
  """
  def process_learning_data(device_id, data, adapter) do
    Logger.info("CommandLearner: Processing data for device #{device_id}, adapter #{adapter}")
    CommandLearningSession.add_data(device_id, data, adapter)
  end

  # Private functions

  defp get_command_from_serial_commands(control_type, zone, opts) do
    alias AmpBridge.HexCommandManager

    case control_type do
      "mute" ->
        case HexCommandManager.get_mute_command(zone) do
          {:ok, hex_chunks} -> {:ok, hex_chunks}
          {:error, :no_mute_command} -> {:error, :no_command}
          {:error, reason} -> {:error, reason}
        end
      "unmute" ->
        case HexCommandManager.get_unmute_command(zone) do
          {:ok, hex_chunks} -> {:ok, hex_chunks}
          {:error, :no_unmute_command} -> {:error, :no_command}
          {:error, reason} -> {:error, reason}
        end
      "turn_off" ->
        case get_turn_off_command(zone) do
          {:ok, hex_chunks} -> {:ok, hex_chunks}
          {:error, :no_command} -> {:error, :no_command}
          {:error, reason} -> {:error, reason}
        end
      "change_source" ->
        case get_change_source_command(zone, opts) do
          {:ok, hex_chunks} -> {:ok, hex_chunks}
          {:error, :no_command} -> {:error, :no_command}
          {:error, reason} -> {:error, reason}
        end
      _ ->
        {:error, :unsupported_control_type}
    end
  end

  defp get_turn_off_command(zone) do
    alias AmpBridge.LearnedCommands

    # Get turn_off command for the zone - handle multiple results by taking the most recent
    case LearnedCommands.get_commands_by_type(1, "turn_off") do
      [] -> {:error, :no_command}
      commands ->
        # Filter commands for the specific zone and take the most recent one
        zone_commands = commands
        |> Enum.filter(&(&1.zone == zone))
        |> Enum.sort_by(& &1.learned_at, {:desc, NaiveDateTime})

        case zone_commands do
          [] -> {:error, :no_command}
          [command | _] ->
            # Convert the command sequence to a list of hex chunks
            # The command_sequence is stored as a single binary, so we need to split it
            # into individual bytes and convert each to a binary chunk
            hex_chunks = command.command_sequence
            |> :binary.bin_to_list()
            |> Enum.map(&<<&1>>)
            {:ok, hex_chunks}
        end
    end
  end

  defp get_change_source_command(zone, opts) do
    alias AmpBridge.LearnedCommands

    # Get source_index from opts
    source_index = Keyword.get(opts, :source_index)

    if source_index == nil do
      {:error, :no_source_index}
    else
      # Get change_source command for the zone and source_index - handle multiple results by taking the most recent
      case LearnedCommands.get_commands_by_type(1, "change_source") do
        [] -> {:error, :no_command}
        commands ->
          # Filter commands for the specific zone and source_index, take the most recent one
          zone_commands = commands
          |> Enum.filter(&(&1.zone == zone && &1.source_index == source_index))
          |> Enum.sort_by(& &1.learned_at, {:desc, NaiveDateTime})

          case zone_commands do
            [] -> {:error, :no_command}
            [command | _] ->
              # Convert the command sequence to a list of hex chunks
              # The command_sequence is stored as a single binary, so we need to split it
              # into individual bytes and convert each to a binary chunk
              hex_chunks = command.command_sequence
              |> :binary.bin_to_list()
              |> Enum.map(&<<&1>>)
              {:ok, hex_chunks}
          end
      end
    end
  end

  defp send_hex_chunks(hex_chunks) do
    # Send each hex chunk via SerialManager
    Enum.each(hex_chunks, fn chunk ->
      case SerialManager.send_command(:adapter_1, chunk) do
        :ok -> :ok
        {:error, reason} ->
          Logger.error("Failed to send hex chunk: #{reason}")
          {:error, reason}
      end
    end)
    :ok
  end

  defp send_command(command_sequence) do
    # Send command via SerialManager
    # This will use the existing serial communication infrastructure
    case SerialManager.send_command(:adapter_2, command_sequence, true) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp group_commands_by_zone(commands) do
    commands
    |> Enum.group_by(& &1.zone)
    |> Enum.map(fn {zone, zone_commands} ->
      {zone, length(zone_commands)}
    end)
    |> Enum.into(%{})
  end
end
