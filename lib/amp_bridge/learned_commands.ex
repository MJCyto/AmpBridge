defmodule AmpBridge.LearnedCommands do
  @moduledoc """
  Context for managing learned amplifier commands.
  """

  import Ecto.Query, warn: false
  alias AmpBridge.Repo
  alias AmpBridge.LearnedCommand

  @doc """
  Get all learned commands for a device.
  """
  def list_commands_for_device(device_id) do
    LearnedCommand
    |> where([c], c.device_id == ^device_id and c.is_active == true)
    |> order_by([c],
      desc: c.learned_at,
      asc: c.control_type,
      asc: c.zone,
      asc: c.source_index,
      asc: c.volume_level
    )
    |> Repo.all()
  end

  @doc """
  Get a specific learned command.
  """
  def get_command(device_id, control_type, zone, opts \\ []) do
    source_index = Keyword.get(opts, :source_index)
    volume_level = Keyword.get(opts, :volume_level)

    query =
      LearnedCommand
      |> where([c], c.device_id == ^device_id)
      |> where([c], c.control_type == ^control_type)
      |> where([c], c.zone == ^zone)
      |> where([c], c.is_active == true)

    query =
      if source_index do
        where(query, [c], c.source_index == ^source_index)
      else
        where(query, [c], is_nil(c.source_index))
      end

    query =
      if volume_level do
        where(query, [c], c.volume_level == ^volume_level)
      else
        where(query, [c], is_nil(c.volume_level))
      end

    Repo.one(query)
  end

  @doc """
  Create a new learned command.
  """
  def create_command(attrs) do
    %LearnedCommand{}
    |> LearnedCommand.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a learned command.
  """
  def update_command(learned_command, attrs) do
    learned_command
    |> LearnedCommand.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Mark a command as used (update last_used timestamp).
  """
  def mark_command_used(learned_command) do
    learned_command
    |> LearnedCommand.update_last_used_changeset()
    |> Repo.update()
  end

  @doc """
  Deactivate a learned command.
  """
  def deactivate_command(learned_command) do
    learned_command
    |> LearnedCommand.changeset(%{is_active: false})
    |> Repo.update()
  end

  @doc """
  Delete a learned command.
  """
  def delete_command(learned_command) do
    Repo.delete(learned_command)
  end

  @doc """
  Get commands by control type for a device.
  """
  def get_commands_by_type(device_id, control_type) do
    LearnedCommand
    |> where([c], c.device_id == ^device_id)
    |> where([c], c.control_type == ^control_type)
    |> where([c], c.is_active == true)
    |> order_by([c], [c.zone, c.source_index, c.volume_level])
    |> Repo.all()
  end

  @doc """
  Get all mute/unmute commands for a device.
  """
  def get_mute_commands(device_id) do
    LearnedCommand
    |> where([c], c.device_id == ^device_id)
    |> where([c], c.control_type in ["mute", "unmute"])
    |> where([c], c.is_active == true)
    |> order_by([c], [c.control_type, c.zone])
    |> Repo.all()
  end

  @doc """
  Get all volume commands for a device.
  """
  def get_volume_commands(device_id) do
    LearnedCommand
    |> where([c], c.device_id == ^device_id)
    |> where([c], c.control_type in ["volume_up", "volume_down", "set_volume"])
    |> where([c], c.is_active == true)
    |> order_by([c], [c.control_type, c.zone, c.volume_level])
    |> Repo.all()
  end

  @doc """
  Get all source change commands for a device.
  """
  def get_source_commands(device_id) do
    LearnedCommand
    |> where([c], c.device_id == ^device_id)
    |> where([c], c.control_type == "change_source")
    |> where([c], c.is_active == true)
    |> order_by([c], [c.zone, c.source_index])
    |> Repo.all()
  end

  @doc """
  Check if a command exists for a specific control action.
  """
  def command_exists?(device_id, control_type, zone, opts \\ []) do
    case get_command(device_id, control_type, zone, opts) do
      nil -> false
      _command -> true
    end
  end

  @doc """
  Get command sequence for a control action, with fallback to default.
  """
  def get_command_sequence(device_id, control_type, zone, opts \\ []) do
    case get_command(device_id, control_type, zone, opts) do
      nil ->
        # Fallback to default command from ZoneManager
        get_default_command_sequence(control_type, zone, opts)

      command ->
        # Mark as used and return learned command
        mark_command_used(command)
        command.command_sequence
    end
  end

  @doc """
  Get response pattern for a control action.
  """
  def get_response_pattern(device_id, control_type, zone, opts \\ []) do
    case get_command(device_id, control_type, zone, opts) do
      nil -> nil
      command -> command.response_pattern
    end
  end

  # Private function to get default command sequences
  # This will integrate with the existing ZoneManager commands
  defp get_default_command_sequence(control_type, zone, opts) do
    # This will be implemented to use existing hardcoded commands
    # from ZoneManager as fallbacks
    case control_type do
      "mute" -> get_default_mute_command(zone)
      "unmute" -> get_default_unmute_command(zone)
      "volume_up" -> get_default_volume_up_command(zone)
      "volume_down" -> get_default_volume_down_command(zone)
      "set_volume" -> get_default_set_volume_command(zone, Keyword.get(opts, :volume_level))
      "change_source" -> get_default_change_source_command(zone, Keyword.get(opts, :source_index))
      _ -> nil
    end
  end

  # Default command implementations - these will use existing ZoneManager logic
  defp get_default_mute_command(_zone) do
    # This will be implemented to return the hardcoded mute command for the zone
    # For now, return nil to indicate no default
    nil
  end

  defp get_default_unmute_command(_zone) do
    # This will be implemented to return the hardcoded unmute command for the zone
    nil
  end

  defp get_default_volume_up_command(_zone) do
    # This will be implemented to return the hardcoded volume up command for the zone
    nil
  end

  defp get_default_volume_down_command(_zone) do
    # This will be implemented to return the hardcoded volume down command for the zone
    nil
  end

  defp get_default_set_volume_command(_zone, _volume_level) do
    # This will be implemented to return the hardcoded set volume command for the zone
    nil
  end

  defp get_default_change_source_command(_zone, _source_index) do
    # This will be implemented to return the hardcoded change source command for the zone
    nil
  end

  @doc """
  Export all learned commands for a device to a JSON structure.
  """
  def export_device_commands(device_id) do
    # Get device info
    device = AmpBridge.Devices.get_device(device_id)

    # Get all learned commands
    learned_commands = list_commands_for_device(device_id)

    # Get serial commands (mute/unmute)
    serial_commands = load_serial_commands_for_export(device_id)

    # Combine all commands
    all_commands = (serial_commands ++ learned_commands)
    |> Enum.sort_by(& &1.learned_at, {:desc, NaiveDateTime})

    # Group commands by zone
    commands_by_zone = Enum.group_by(all_commands, & &1.zone)

    # Build export structure
    %{
      "metadata" => %{
        "export_version" => "1.0",
        "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "device_info" => %{
          "device_id" => device_id,
          "device_name" => if(device, do: device.name, else: nil),
          "device_model" => if(device, do: Map.get(device, :model, nil), else: nil),
          "device_manufacturer" => if(device, do: Map.get(device, :manufacturer, nil), else: nil)
        },
        "total_zones" => length(Map.keys(commands_by_zone)),
        "total_commands" => length(all_commands)
      },
      "zones" => build_zones_export(commands_by_zone, device) |> Enum.into(%{}, fn zone -> {zone["zone_number"], zone} end)
    }
  end

  @doc """
  Import commands from a JSON structure.
  """
  def import_device_commands(device_id, json_data) do
    with {:ok, parsed_data} <- Jason.decode(json_data),
         {:ok, _metadata} <- validate_import_metadata(parsed_data),
         {:ok, zones} <- validate_zones_structure(parsed_data["zones"]),
         {:ok, commands} <- parse_imported_commands(device_id, zones) do

      # Import commands to database
      import_results = Enum.map(commands, &import_single_command/1)

      successful_imports = Enum.count(import_results, &match?({:ok, _}, &1))
      failed_imports = Enum.count(import_results, &match?({:error, _}, &1))

      {:ok, %{
        successful_imports: successful_imports,
        failed_imports: failed_imports,
        total_commands: length(commands)
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private helper functions for export
  defp load_serial_commands_for_export(_device_id) do
    alias AmpBridge.Repo
    alias AmpBridge.SerialCommand

    Repo.all(SerialCommand)
    |> Enum.flat_map(fn serial_command ->
      zone = serial_command.zone_index
      commands = []

      # Add mute command if exists
      commands = if serial_command.mute != "[]" do
        mute_sequence = decode_serial_command(serial_command.mute)
        [%{
          control_type: "mute",
          zone: zone,
          source_index: nil,
          volume_level: nil,
          command_sequence: mute_sequence,
          response_pattern: nil,
          learned_at: serial_command.updated_at,
          is_active: true
        } | commands]
      else
        commands
      end

      # Add unmute command if exists
      commands = if serial_command.unmute != "[]" do
        unmute_sequence = decode_serial_command(serial_command.unmute)
        [%{
          control_type: "unmute",
          zone: zone,
          source_index: nil,
          volume_level: nil,
          command_sequence: unmute_sequence,
          response_pattern: nil,
          learned_at: serial_command.updated_at,
          is_active: true
        } | commands]
      else
        commands
      end

      commands
    end)
  end

  defp decode_serial_command(json_string) do
    case Jason.decode(json_string) do
      {:ok, base64_array} ->
        base64_array
        |> Enum.map(fn base64_binary ->
          case Base.decode64(base64_binary) do
            {:ok, binary} -> binary
            {:error, _} -> <<0>>
          end
        end)
        |> :erlang.list_to_binary()
      {:error, _} -> <<>>
    end
  end

  defp build_zones_export(commands_by_zone, device) do
    commands_by_zone
    |> Enum.map(fn {zone, commands} ->
      zone_name = get_zone_name_from_device(device, zone)

      %{
        "zone_number" => zone,
        "zone_name" => zone_name || "Zone #{zone + 1}",
        "commands" => Enum.map(commands, &build_command_export/1)
      }
    end)
    |> Enum.sort_by(& &1["zone_number"])
  end

  defp get_zone_name_from_device(device, zone) do
    if device && device.zones do
      zone_key = to_string(zone)
      case Map.get(device.zones, zone_key) do
        %{"name" => name} when is_binary(name) and name != "" -> name
        _ -> nil
      end
    else
      nil
    end
  end

  defp build_command_export(command) do
    %{
      "control_type" => command.control_type,
      "zone" => command.zone,
      "source_index" => command.source_index,
      "volume_level" => command.volume_level,
      "command_sequence" => Base.encode64(command.command_sequence),
      "response_pattern" => if(command.response_pattern, do: Base.encode64(command.response_pattern), else: nil),
      "learned_at" => command.learned_at |> NaiveDateTime.to_iso8601(),
      "is_active" => command.is_active
    }
  end

  # Private helper functions for import
  defp validate_import_metadata(data) do
    case Map.get(data, "metadata") do
      nil -> {:error, "Missing metadata section"}
      metadata ->
        if Map.get(metadata, "export_version") do
          {:ok, metadata}
        else
          {:error, "Invalid export version"}
        end
    end
  end

  defp validate_zones_structure(zones) when is_map(zones) do
    {:ok, zones}
  end
  defp validate_zones_structure(zones) when is_list(zones) do
    # Handle legacy format where zones is a list
    zones_map = Enum.into(zones, %{}, fn zone -> {zone["zone_number"], zone} end)
    {:ok, zones_map}
  end
  defp validate_zones_structure(_), do: {:error, "Invalid zones structure"}

  defp parse_imported_commands(device_id, zones) do
    commands = zones
    |> Enum.flat_map(fn {_zone_key, zone_data} ->
      zone_number = Map.get(zone_data, "zone_number")
      zone_commands = Map.get(zone_data, "commands", [])

      Enum.map(zone_commands, fn command_data ->
        parse_single_command(device_id, zone_number, command_data)
      end)
    end)
    |> Enum.reject(&is_nil/1)

    if length(commands) == 0 do
      {:error, "No valid commands found in import file"}
    else
      {:ok, commands}
    end
  end

  defp parse_single_command(device_id, zone_number, command_data) do
    with {:ok, control_type} <- validate_control_type(Map.get(command_data, "control_type")),
         {:ok, command_sequence} <- decode_command_sequence(Map.get(command_data, "command_sequence")),
         {:ok, response_pattern} <- decode_response_pattern(Map.get(command_data, "response_pattern")) do

      %{
        device_id: device_id,
        control_type: control_type,
        zone: zone_number,
        source_index: Map.get(command_data, "source_index"),
        volume_level: Map.get(command_data, "volume_level"),
        command_sequence: command_sequence,
        response_pattern: response_pattern,
        learned_at: parse_learned_at(Map.get(command_data, "learned_at")),
        is_active: Map.get(command_data, "is_active", true)
      }
    else
      {:error, _} -> nil
    end
  end

  defp validate_control_type(control_type) when control_type in [
    "mute", "unmute", "volume_up", "volume_down", "set_volume", "change_source", "turn_off"
  ] do
    {:ok, control_type}
  end
  defp validate_control_type(_), do: {:error, "Invalid control type"}

  defp decode_command_sequence(nil), do: {:error, "Missing command sequence"}
  defp decode_command_sequence(base64_string) do
    case Base.decode64(base64_string) do
      {:ok, binary} -> {:ok, binary}
      {:error, _} -> {:error, "Invalid base64 command sequence"}
    end
  end

  defp decode_response_pattern(nil), do: {:ok, nil}
  defp decode_response_pattern(base64_string) do
    case Base.decode64(base64_string) do
      {:ok, binary} -> {:ok, binary}
      {:error, _} -> {:error, "Invalid base64 response pattern"}
    end
  end

  defp parse_learned_at(nil), do: NaiveDateTime.utc_now()
  defp parse_learned_at(iso_string) do
    case NaiveDateTime.from_iso8601(iso_string) do
      {:ok, naive_dt, _} -> naive_dt
      {:error, _} -> NaiveDateTime.utc_now()
    end
  end

  defp import_single_command(command_attrs) do
    create_command(command_attrs)
  end
end
