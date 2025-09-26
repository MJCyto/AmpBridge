defmodule AmpBridge.HexCommandManager do
  @moduledoc """
  Manager for preparing hex command sequences from the database.
  Converts binary blobs to lists of individual hex values for serial transmission.
  """

  alias AmpBridge.Repo
  alias AmpBridge.SerialCommand

  # Volume encoding formulas - each zone has a specific encoding formula value
  @volume_encoding_formulas %{
    1 => 218,
    2 => 217,
    3 => 216,
    4 => 215,
    5 => 214,
    6 => 213,
    7 => 212,
    8 => 211
  }


  @doc """
  Get mute command as a list of hex values for the specified zone.
  Returns {:ok, hex_list} or {:error, reason}
  """
  def get_mute_command(zone_index) when zone_index in 0..7 do
    case Repo.get(SerialCommand, zone_index) do
      nil -> {:error, :zone_not_found}
      %SerialCommand{mute: "[]"} -> {:error, :no_mute_command}
      %SerialCommand{mute: mute_json} ->
        case Jason.decode(mute_json) do
          {:ok, mute_array} ->
            hex_values = Enum.map(mute_array, fn base64_binary ->
              case Base.decode64(base64_binary) do
                {:ok, binary} -> binary
                {:error, _} -> <<>>
              end
            end)
            {:ok, hex_values}
          {:error, _} -> {:error, :invalid_mute_data}
        end
    end
  end

  def get_mute_command(_zone_index), do: {:error, :invalid_zone}

  @doc """
  Get unmute command as a list of hex values for the specified zone.
  Returns {:ok, hex_list} or {:error, reason}
  """
  def get_unmute_command(zone_index) when zone_index in 0..7 do
    case Repo.get(SerialCommand, zone_index) do
      nil -> {:error, :zone_not_found}
      %SerialCommand{unmute: "[]"} -> {:error, :no_unmute_command}
      %SerialCommand{unmute: unmute_json} ->
        case Jason.decode(unmute_json) do
          {:ok, unmute_array} ->
            hex_values = Enum.map(unmute_array, fn base64_binary ->
              case Base.decode64(base64_binary) do
                {:ok, binary} -> binary
                {:error, _} -> <<>>
              end
            end)
            {:ok, hex_values}
          {:error, _} -> {:error, :invalid_unmute_data}
        end
    end
  end

  def get_unmute_command(_zone_index), do: {:error, :invalid_zone}

  @doc """
  Get all commands for a zone as a map.
  Returns {:ok, %{mute: [hex_list], unmute: [hex_list]}} or {:error, reason}
  """
  def get_all_commands_for_zone(zone_index) when zone_index in 0..7 do
    case Repo.get(SerialCommand, zone_index) do
      nil -> {:error, :zone_not_found}
      %SerialCommand{mute: mute_json, unmute: unmute_json} ->
        with {:ok, mute_array} <- Jason.decode(mute_json),
             {:ok, unmute_array} <- Jason.decode(unmute_json) do
          mute_hex = Enum.map(mute_array, fn base64_binary ->
            case Base.decode64(base64_binary) do
              {:ok, binary} -> binary
              {:error, _} -> <<>>
            end
          end)
          unmute_hex = Enum.map(unmute_array, fn base64_binary ->
            case Base.decode64(base64_binary) do
              {:ok, binary} -> binary
              {:error, _} -> <<>>
            end
          end)
          commands = %{mute: mute_hex, unmute: unmute_hex}
          {:ok, commands}
        else
          {:error, _} -> {:error, :invalid_command_data}
        end
    end
  end

  def get_all_commands_for_zone(_zone_index), do: {:error, :invalid_zone}

  @doc """
  Check if a command exists for a zone.
  Returns true/false
  """
  def command_exists?(zone_index, command_type) when command_type in [:mute, :unmute] do
    case Repo.get(SerialCommand, zone_index) do
      nil -> false
      %SerialCommand{} = command ->
        case command_type do
          :mute -> command.mute != "[]"
          :unmute -> command.unmute != "[]"
        end
    end
  end

  def command_exists?(_zone_index, _command_type), do: false

  @doc """
  Update a command for a zone.
  Returns {:ok, serial_command} or {:error, changeset}
  """
  def update_command(zone_index, command_type, hex_values) when command_type in [:mute, :unmute] do
    case Repo.get(SerialCommand, zone_index) do
      nil -> {:error, :zone_not_found}
      serial_command ->
        binary_array = Enum.map(hex_values, fn hex_value -> <<hex_value>> end)
        base64_array = Enum.map(binary_array, &Base.encode64/1)
        json_data = Jason.encode!(base64_array)

        attrs = case command_type do
          :mute -> %{mute: json_data}
          :unmute -> %{unmute: json_data}
        end

        serial_command
        |> SerialCommand.changeset(attrs)
        |> Repo.update()
    end
  end

  def update_command(_zone_index, _command_type, _hex_values), do: {:error, :invalid_command_type}

  # Volume Control Functions

  @doc """
  Get volume command as a list of hex values for the specified zone and volume level.
  Returns {:ok, hex_list} or {:error, reason}
  """
  def get_volume_command(zone_index, volume_percentage) when zone_index in 1..8 and volume_percentage in 0..100 do
    encoding_formula = get_volume_encoding_formula(zone_index)
    volume_byte1 = volume_percentage
    volume_byte2 = encoding_formula - volume_percentage
    command_bytes = [0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, zone_index, volume_byte1, volume_byte2]
    checksum = calculate_checksum(command_bytes)

    hex_values = create_zone_specific_volume_chunks(zone_index, volume_byte1, volume_byte2, checksum)
    {:ok, hex_values}
  end

  def get_volume_command(_zone_index, _volume_percentage), do: {:error, :invalid_parameters}


  # Private helper functions

  defp get_volume_encoding_formula(zone) do
    # Default to 217 if zone not found
    Map.get(@volume_encoding_formulas, zone, 217)
  end

  defp calculate_checksum(command_bytes) do
    sum = Enum.sum(command_bytes)
    Bitwise.bxor(Bitwise.band(sum, 0xFF), 0x52)
  end

  defp create_zone_specific_volume_chunks(zone, volume_byte1, volume_byte2, checksum) do
    case zone do
      1 ->
        # Zone 1: Different chunking pattern
        # [A4 05] [06 FF] [0B] [10] [01] [volume_byte1 volume_byte2] [checksum]
        [
          <<0xA4, 0x05>>,
          <<0x06, 0xFF>>,
          <<0x0B>>,
          <<0x10>>,
          <<0x01>>,
          <<volume_byte1, volume_byte2>>,
          <<checksum>>
        ]

      _ ->
        # Zone 2 and others: Original chunking pattern
        # [A4 05] [06 FF 0B] [10 zone] [volume_byte1 volume_byte2] [checksum]
        [
          <<0xA4, 0x05>>,
          <<0x06, 0xFF, 0x0B>>,
          <<0x10, zone>>,
          <<volume_byte1, volume_byte2>>,
          <<checksum>>
        ]
    end
  end
end
