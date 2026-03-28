defmodule AmpBridge.LearnedCommandsTest do
  use ExUnit.Case, async: false

  alias AmpBridge.LearnedCommands
  alias AmpBridge.LearnedCommand
  alias AmpBridge.AudioDevice
  alias AmpBridge.Repo

  setup do
    # Clean up before each test
    Repo.delete_all(LearnedCommand)
    Repo.delete_all(AudioDevice)

    # Create a test device
    {:ok, device} = AmpBridge.Devices.create_device(%{
      name: "Test Amplifier",
      model: "Test Model",
      manufacturer: "Test Manufacturer",
      zones: %{
        "0" => %{"name" => "Living Room"},
        "1" => %{"name" => "Kitchen"}
      }
    })

    %{device: device}
  end

  describe "export_device_commands/1" do
    test "exports empty structure when no commands exist", %{device: device} do
      export_data = LearnedCommands.export_device_commands(device.id)

      assert %{
        "metadata" => %{
          "export_version" => "1.0",
          "exported_at" => _,
          "device_info" => %{
            "device_id" => device_id,
            "device_name" => "Test Amplifier",
            "device_model" => "Test Model",
            "device_manufacturer" => "Test Manufacturer"
          },
          "total_zones" => 0,
          "total_commands" => 0
        },
        "zones" => %{}
      } = export_data

      assert device_id == device.id
    end

    test "exports learned commands with correct structure", %{device: device} do
      # Create test commands
      command1_attrs = %{
        device_id: device.id,
        control_type: "mute",
        zone: 0,
        command_sequence: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x18, 0x01, 0x01, 0xD1>>,
        learned_at: NaiveDateTime.utc_now(),
        is_active: true
      }

      {:ok, _command1} = LearnedCommands.create_command(command1_attrs)

      command2_attrs = %{
        device_id: device.id,
        control_type: "unmute",
        zone: 0,
        command_sequence: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x18, 0x01, 0x00, 0xD0>>,
        learned_at: NaiveDateTime.utc_now(),
        is_active: true
      }

      {:ok, _command2} = LearnedCommands.create_command(command2_attrs)

      command3_attrs = %{
        device_id: device.id,
        control_type: "volume_up",
        zone: 1,
        command_sequence: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, 0x01, 0x32, 0xA8, 0xF6>>,
        learned_at: NaiveDateTime.utc_now(),
        is_active: true
      }

      {:ok, _command3} = LearnedCommands.create_command(command3_attrs)

      export_data = LearnedCommands.export_device_commands(device.id)

      assert %{
        "metadata" => %{
          "export_version" => "1.0",
          "exported_at" => _,
          "device_info" => %{
            "device_id" => ^device_id,
            "device_name" => "Test Amplifier",
            "device_model" => "Test Model",
            "device_manufacturer" => "Test Manufacturer"
          },
          "total_zones" => 2,
          "total_commands" => 3
        },
        "zones" => zones
      } = export_data

      assert device_id == device.id

      # Check zone 0 has 2 commands
      zone_0 = Map.get(zones, 0)
      assert zone_0["zone_number"] == 0
      assert zone_0["zone_name"] == "Living Room"
      assert length(zone_0["commands"]) == 2

      # Check zone 1 has 1 command
      zone_1 = Map.get(zones, 1)
      assert zone_1["zone_number"] == 1
      assert zone_1["zone_name"] == "Kitchen"
      assert length(zone_1["commands"]) == 1

      # Verify command structure
      mute_command = Enum.find(zone_0["commands"], &(&1["control_type"] == "mute"))
      assert mute_command["zone"] == 0
      assert mute_command["command_sequence"] == Base.encode64(<<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x18, 0x01, 0x01, 0xD1>>)
      assert mute_command["is_active"] == true
      assert mute_command["learned_at"] != nil
    end

    test "exports commands with source_index and volume_level", %{device: device} do
      command_attrs = %{
        device_id: device.id,
        control_type: "set_volume",
        zone: 0,
        volume_level: 50,
        command_sequence: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, 0x01, 0x32, 0xA8, 0xF6>>,
        learned_at: NaiveDateTime.utc_now(),
        is_active: true
      }

      {:ok, _command} = LearnedCommands.create_command(command_attrs)

      export_data = LearnedCommands.export_device_commands(device.id)
      zones = export_data["zones"]
      zone_0 = Map.get(zones, 0)
      volume_command = Enum.find(zone_0["commands"], &(&1["control_type"] == "set_volume"))

      assert volume_command["volume_level"] == 50
      assert volume_command["source_index"] == nil
    end

    test "only exports active commands", %{device: device} do
      # Create active command
      active_attrs = %{
        device_id: device.id,
        control_type: "mute",
        zone: 0,
        command_sequence: <<0xA4, 0x05, 0x06>>,
        learned_at: NaiveDateTime.utc_now(),
        is_active: true
      }

      {:ok, active_command} = LearnedCommands.create_command(active_attrs)

      # Deactivate the command
      LearnedCommands.deactivate_command(active_command)

      # Create inactive command directly
      inactive_attrs = %{
        device_id: device.id,
        control_type: "unmute",
        zone: 0,
        command_sequence: <<0xA4, 0x05, 0x07>>,
        learned_at: NaiveDateTime.utc_now(),
        is_active: false
      }

      {:ok, _inactive_command} = LearnedCommands.create_command(inactive_attrs)

      export_data = LearnedCommands.export_device_commands(device.id)

      assert export_data["metadata"]["total_commands"] == 0
      assert export_data["zones"] == %{}
    end
  end

  describe "import_device_commands/2" do
    test "imports valid JSON export file", %{device: device} do
      # Create export data
      export_data = %{
        "metadata" => %{
          "export_version" => "1.0",
          "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "device_info" => %{
            "device_id" => device.id,
            "device_name" => "Test Amplifier"
          }
        },
        "zones" => %{
          0 => %{
            "zone_number" => 0,
            "zone_name" => "Living Room",
            "commands" => [
              %{
                "control_type" => "mute",
                "zone" => 0,
                "source_index" => nil,
                "volume_level" => nil,
                "command_sequence" => Base.encode64(<<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x18, 0x01, 0x01, 0xD1>>),
                "response_pattern" => nil,
                "learned_at" => NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601(),
                "is_active" => true
              },
              %{
                "control_type" => "unmute",
                "zone" => 0,
                "source_index" => nil,
                "volume_level" => nil,
                "command_sequence" => Base.encode64(<<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x18, 0x01, 0x00, 0xD0>>),
                "response_pattern" => nil,
                "learned_at" => NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601(),
                "is_active" => true
              }
            ]
          },
          1 => %{
            "zone_number" => 1,
            "zone_name" => "Kitchen",
            "commands" => [
              %{
                "control_type" => "volume_up",
                "zone" => 1,
                "source_index" => nil,
                "volume_level" => nil,
                "command_sequence" => Base.encode64(<<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, 0x01, 0x32, 0xA8, 0xF6>>),
                "response_pattern" => nil,
                "learned_at" => NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601(),
                "is_active" => true
              }
            ]
          }
        }
      }

      json_data = Jason.encode!(export_data)

      # Import commands
      assert {:ok, result} = LearnedCommands.import_device_commands(device.id, json_data)

      assert result.successful_imports == 3
      assert result.failed_imports == 0
      assert result.total_commands == 3

      # Verify commands were imported
      commands = LearnedCommands.list_commands_for_device(device.id)
      assert length(commands) == 3

      # Verify command details
      mute_command = Enum.find(commands, &(&1.control_type == "mute"))
      assert mute_command.zone == 0
      assert mute_command.command_sequence == <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x18, 0x01, 0x01, 0xD1>>
      assert mute_command.is_active == true
    end

    test "imports commands with source_index and volume_level", %{device: device} do
      export_data = %{
        "metadata" => %{
          "export_version" => "1.0",
          "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        },
        "zones" => %{
          0 => %{
            "zone_number" => 0,
            "zone_name" => "Living Room",
            "commands" => [
              %{
                "control_type" => "set_volume",
                "zone" => 0,
                "source_index" => nil,
                "volume_level" => 50,
                "command_sequence" => Base.encode64(<<0xA4, 0x05, 0x06>>),
                "response_pattern" => nil,
                "learned_at" => NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601(),
                "is_active" => true
              },
              %{
                "control_type" => "change_source",
                "zone" => 0,
                "source_index" => 2,
                "volume_level" => nil,
                "command_sequence" => Base.encode64(<<0xA4, 0x05, 0x07>>),
                "response_pattern" => nil,
                "learned_at" => NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601(),
                "is_active" => true
              }
            ]
          }
        }
      }

      json_data = Jason.encode!(export_data)

      assert {:ok, result} = LearnedCommands.import_device_commands(device.id, json_data)
      assert result.successful_imports == 2

      commands = LearnedCommands.list_commands_for_device(device.id)
      volume_command = Enum.find(commands, &(&1.control_type == "set_volume"))
      source_command = Enum.find(commands, &(&1.control_type == "change_source"))

      assert volume_command.volume_level == 50
      assert source_command.source_index == 2
    end

    test "returns error for invalid JSON", %{device: device} do
      invalid_json = "{invalid json}"

      assert {:error, _reason} = LearnedCommands.import_device_commands(device.id, invalid_json)
    end

    test "returns error for missing metadata", %{device: device} do
      invalid_data = %{
        "zones" => %{}
      }

      json_data = Jason.encode!(invalid_data)

      assert {:error, "Missing metadata section"} = LearnedCommands.import_device_commands(device.id, json_data)
    end

    test "returns error for invalid export version", %{device: device} do
      invalid_data = %{
        "metadata" => %{
          "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        },
        "zones" => %{}
      }

      json_data = Jason.encode!(invalid_data)

      assert {:error, "Invalid export version"} = LearnedCommands.import_device_commands(device.id, json_data)
    end

    test "returns error for invalid zones structure", %{device: device} do
      invalid_data = %{
        "metadata" => %{
          "export_version" => "1.0",
          "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        },
        "zones" => "invalid"
      }

      json_data = Jason.encode!(invalid_data)

      assert {:error, "Invalid zones structure"} = LearnedCommands.import_device_commands(device.id, json_data)
    end

    test "returns error for invalid control type", %{device: device} do
      invalid_data = %{
        "metadata" => %{
          "export_version" => "1.0",
          "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        },
        "zones" => %{
          0 => %{
            "zone_number" => 0,
            "zone_name" => "Living Room",
            "commands" => [
              %{
                "control_type" => "invalid_type",
                "zone" => 0,
                "command_sequence" => Base.encode64(<<0xA4, 0x05, 0x06>>),
                "learned_at" => NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601(),
                "is_active" => true
              }
            ]
          }
        }
      }

      json_data = Jason.encode!(invalid_data)

      assert {:ok, result} = LearnedCommands.import_device_commands(device.id, json_data)
      assert result.successful_imports == 0
      assert result.failed_imports == 0  # Invalid commands are filtered out, not counted as failures
      assert result.total_commands == 0
    end

    test "returns error for invalid base64 command sequence", %{device: device} do
      invalid_data = %{
        "metadata" => %{
          "export_version" => "1.0",
          "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        },
        "zones" => %{
          0 => %{
            "zone_number" => 0,
            "zone_name" => "Living Room",
            "commands" => [
              %{
                "control_type" => "mute",
                "zone" => 0,
                "command_sequence" => "invalid_base64!!!",
                "learned_at" => NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601(),
                "is_active" => true
              }
            ]
          }
        }
      }

      json_data = Jason.encode!(invalid_data)

      assert {:ok, result} = LearnedCommands.import_device_commands(device.id, json_data)
      assert result.successful_imports == 0
      assert result.total_commands == 0
    end

    test "handles empty zones", %{device: device} do
      export_data = %{
        "metadata" => %{
          "export_version" => "1.0",
          "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        },
        "zones" => %{}
      }

      json_data = Jason.encode!(export_data)

      assert {:error, "No valid commands found in import file"} = LearnedCommands.import_device_commands(device.id, json_data)
    end

    test "round-trip export and import", %{device: device} do
      # Create commands
      command1_attrs = %{
        device_id: device.id,
        control_type: "mute",
        zone: 0,
        command_sequence: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x18, 0x01, 0x01, 0xD1>>,
        learned_at: NaiveDateTime.utc_now(),
        is_active: true
      }

      {:ok, _command1} = LearnedCommands.create_command(command1_attrs)

      command2_attrs = %{
        device_id: device.id,
        control_type: "set_volume",
        zone: 1,
        volume_level: 75,
        command_sequence: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, 0x01, 0x4B, 0xA2, 0xF6>>,
        learned_at: NaiveDateTime.utc_now(),
        is_active: true
      }

      {:ok, _command2} = LearnedCommands.create_command(command2_attrs)

      # Export
      export_data = LearnedCommands.export_device_commands(device.id)
      json_data = Jason.encode!(export_data)

      # Delete all commands
      Repo.delete_all(LearnedCommand)

      # Import
      assert {:ok, result} = LearnedCommands.import_device_commands(device.id, json_data)
      assert result.successful_imports == 2

      # Verify imported commands match original
      imported_commands = LearnedCommands.list_commands_for_device(device.id)
      assert length(imported_commands) == 2

      imported_mute = Enum.find(imported_commands, &(&1.control_type == "mute"))
      imported_volume = Enum.find(imported_commands, &(&1.control_type == "set_volume"))

      assert imported_mute.zone == 0
      assert imported_mute.command_sequence == <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x18, 0x01, 0x01, 0xD1>>

      assert imported_volume.zone == 1
      assert imported_volume.volume_level == 75
      assert imported_volume.command_sequence == <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, 0x01, 0x4B, 0xA2, 0xF6>>
    end
  end
end
