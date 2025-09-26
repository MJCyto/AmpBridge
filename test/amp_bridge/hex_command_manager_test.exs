defmodule AmpBridge.HexCommandManagerTest do
  use ExUnit.Case, async: false

  alias AmpBridge.HexCommandManager
  alias AmpBridge.SerialCommand
  alias AmpBridge.Repo

  setup do
    # Clean up any existing data before each test
    Repo.delete_all(SerialCommand)
    :ok
  end

  describe "get_mute_command/1" do
    test "returns hex list for zone with mute command" do
      # Insert test data
      mute_binaries = [<<0xA4>>, <<0x05>>, <<0x06>>, <<0xFF>>, <<0x0B>>, <<0x18>>, <<0x01>>, <<0x01>>, <<0xD1>>]
      mute_data = Jason.encode!(Enum.map(mute_binaries, &Base.encode64/1))
      %SerialCommand{}
      |> SerialCommand.changeset(%{
        zone_index: 0,
        mute: mute_data
      })
      |> Repo.insert!()

      assert {:ok, [<<0xA4>>, <<0x05>>, <<0x06>>, <<0xFF>>, <<0x0B>>, <<0x18>>, <<0x01>>, <<0x01>>, <<0xD1>>]} = HexCommandManager.get_mute_command(0)
    end

    test "returns error for zone without mute command" do
      # Insert test data with empty mute
      %SerialCommand{}
      |> SerialCommand.changeset(%{zone_index: 1, mute: "[]"})
      |> Repo.insert!()

      assert {:error, :no_mute_command} = HexCommandManager.get_mute_command(1)
    end

    test "returns error for non-existent zone" do
      assert {:error, :zone_not_found} = HexCommandManager.get_mute_command(0)
    end

    test "returns error for invalid zone" do
      assert {:error, :invalid_zone} = HexCommandManager.get_mute_command(8)
      assert {:error, :invalid_zone} = HexCommandManager.get_mute_command(-1)
    end
  end

  describe "get_unmute_command/1" do
    test "returns hex list for zone with unmute command" do
      # Insert test data
      unmute_binaries = [<<0xB4>>, <<0x15>>, <<0x16>>, <<0x0F>>, <<0x1B>>, <<0x28>>, <<0x11>>, <<0x11>>, <<0xE1>>]
      unmute_data = Jason.encode!(Enum.map(unmute_binaries, &Base.encode64/1))
      %SerialCommand{}
      |> SerialCommand.changeset(%{
        zone_index: 0,
        unmute: unmute_data
      })
      |> Repo.insert!()

      assert {:ok, [<<0xB4>>, <<0x15>>, <<0x16>>, <<0x0F>>, <<0x1B>>, <<0x28>>, <<0x11>>, <<0x11>>, <<0xE1>>]} = HexCommandManager.get_unmute_command(0)
    end

    test "returns error for zone without unmute command" do
      # Insert test data with empty unmute
      %SerialCommand{}
      |> SerialCommand.changeset(%{zone_index: 1, unmute: "[]"})
      |> Repo.insert!()

      assert {:error, :no_unmute_command} = HexCommandManager.get_unmute_command(1)
    end

    test "returns error for non-existent zone" do
      assert {:error, :zone_not_found} = HexCommandManager.get_unmute_command(0)
    end

    test "returns error for invalid zone" do
      assert {:error, :invalid_zone} = HexCommandManager.get_unmute_command(8)
      assert {:error, :invalid_zone} = HexCommandManager.get_unmute_command(-1)
    end
  end

  describe "get_all_commands_for_zone/1" do
    test "returns all commands for zone" do
      # Insert test data
      mute_binaries = [<<0xA4>>, <<0x05>>, <<0x06>>]
      unmute_binaries = [<<0xB4>>, <<0x15>>, <<0x16>>]
      mute_data = Jason.encode!(Enum.map(mute_binaries, &Base.encode64/1))
      unmute_data = Jason.encode!(Enum.map(unmute_binaries, &Base.encode64/1))
      %SerialCommand{}
      |> SerialCommand.changeset(%{
        zone_index: 0,
        mute: mute_data,
        unmute: unmute_data
      })
      |> Repo.insert!()

      assert {:ok, %{mute: [<<0xA4>>, <<0x05>>, <<0x06>>], unmute: [<<0xB4>>, <<0x15>>, <<0x16>>]}} =
        HexCommandManager.get_all_commands_for_zone(0)
    end

    test "returns empty lists for zone with no commands" do
      # Insert test data with empty commands
      %SerialCommand{}
      |> SerialCommand.changeset(%{zone_index: 1, mute: "[]", unmute: "[]"})
      |> Repo.insert!()

      assert {:ok, %{mute: [], unmute: []}} = HexCommandManager.get_all_commands_for_zone(1)
    end

    test "returns error for non-existent zone" do
      assert {:error, :zone_not_found} = HexCommandManager.get_all_commands_for_zone(0)
    end

    test "returns error for invalid zone" do
      assert {:error, :invalid_zone} = HexCommandManager.get_all_commands_for_zone(8)
      assert {:error, :invalid_zone} = HexCommandManager.get_all_commands_for_zone(-1)
    end
  end

  describe "command_exists?/2" do
    test "returns true when command exists" do
      # Insert test data
      mute_binaries = [<<0xA4>>, <<0x05>>, <<0x06>>]
      mute_data = Jason.encode!(Enum.map(mute_binaries, &Base.encode64/1))
      %SerialCommand{}
      |> SerialCommand.changeset(%{
        zone_index: 0,
        mute: mute_data,
        unmute: "[]"
      })
      |> Repo.insert!()

      assert HexCommandManager.command_exists?(0, :mute) == true
      assert HexCommandManager.command_exists?(0, :unmute) == false
    end

    test "returns false for non-existent zone" do
      assert HexCommandManager.command_exists?(0, :mute) == false
    end

    test "returns false for invalid command type" do
      assert HexCommandManager.command_exists?(0, :invalid) == false
    end
  end

  describe "update_command/3" do
    test "updates mute command successfully" do
      # Insert test data
      %SerialCommand{}
      |> SerialCommand.changeset(%{zone_index: 0, mute: "[]", unmute: "[]"})
      |> Repo.insert!()

      hex_values = [0xA4, 0x05, 0x06, 0xFF]
      assert {:ok, %SerialCommand{}} = HexCommandManager.update_command(0, :mute, hex_values)

      # Verify the update
      assert {:ok, [<<0xA4>>, <<0x05>>, <<0x06>>, <<0xFF>>]} = HexCommandManager.get_mute_command(0)
    end

    test "updates unmute command successfully" do
      # Insert test data
      %SerialCommand{}
      |> SerialCommand.changeset(%{zone_index: 0, mute: "[]", unmute: "[]"})
      |> Repo.insert!()

      hex_values = [0xB4, 0x15, 0x16, 0x0F]
      assert {:ok, %SerialCommand{}} = HexCommandManager.update_command(0, :unmute, hex_values)

      # Verify the update
      assert {:ok, [<<0xB4>>, <<0x15>>, <<0x16>>, <<0x0F>>]} = HexCommandManager.get_unmute_command(0)
    end

    test "returns error for non-existent zone" do
      assert {:error, :zone_not_found} = HexCommandManager.update_command(0, :mute, [0xA4])
    end

    test "returns error for invalid command type" do
      assert {:error, :invalid_command_type} = HexCommandManager.update_command(0, :invalid, [0xA4])
    end
  end

  # Volume Control Tests

  describe "volume control functions" do
    test "get_volume_command returns correct volume command for zone 1" do
      {:ok, result} = HexCommandManager.get_volume_command(1, 50)

      # Convert to flat hex values for verification
      hex_values = Enum.flat_map(result, fn chunk -> :binary.bin_to_list(chunk) end)

      # Expected: [164, 5, 6, 255, 11, 16, 1, 50, 168, 246]
      assert hex_values == [164, 5, 6, 255, 11, 16, 1, 50, 168, 246]
    end

    test "get_volume_command returns correct volume command for zone 2" do
      {:ok, result} = HexCommandManager.get_volume_command(2, 75)

      hex_values = Enum.flat_map(result, fn chunk -> :binary.bin_to_list(chunk) end)

      # Expected: [164, 5, 6, 255, 11, 16, 2, 75, 142, checksum]
      # Zone 2 formula: 217, so volume_byte2 = 217 - 75 = 142
      assert length(hex_values) == 10
      assert Enum.take(hex_values, 7) == [164, 5, 6, 255, 11, 16, 2]
      assert Enum.at(hex_values, 7) == 75  # volume_byte1
      assert Enum.at(hex_values, 8) == 142  # volume_byte2
    end


    test "get_volume_command with invalid parameters returns error" do
      assert HexCommandManager.get_volume_command(0, 50) == {:error, :invalid_parameters}
      assert HexCommandManager.get_volume_command(1, 150) == {:error, :invalid_parameters}
      assert HexCommandManager.get_volume_command(9, 50) == {:error, :invalid_parameters}
    end

    test "volume commands work for all zones 1-8" do
      for zone <- 1..8 do
        # Test volume command
        {:ok, volume_result} = HexCommandManager.get_volume_command(zone, 50)
        assert is_list(volume_result)
        assert length(volume_result) > 0
      end
    end
  end
end
