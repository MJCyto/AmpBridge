defmodule AmpBridge.Repo.Migrations.CreateSerialCommands do
  use Ecto.Migration

  def change do
    create table(:serial_commands, primary_key: false) do
      add(:zone_index, :integer, primary_key: true)
      add(:mute, :text, null: false, default: "[]")
      add(:unmute, :text, null: false, default: "[]")

      timestamps()
    end

    # Insert initial data for all 8 zones with mute and unmute commands
    # Zone 0: mute=0xA4,0x05,0x06,0xFF,0x0B,0x18,0x01,0x01,0xD1 | unmute=0xA4,0x05,0x06,0xFF,0x0B,0x18,0x01,0x00,0xD2
    execute("INSERT INTO serial_commands (zone_index, mute, unmute, inserted_at, updated_at) VALUES (0, '[\"pA==\",\"BQ==\",\"Bg==\",\"/w==\",\"Cw==\",\"GA==\",\"AQ==\",\"AQ==\",\"0Q==\"]', '[\"pA==\",\"BQ==\",\"Bg==\",\"/w==\",\"Cw==\",\"GA==\",\"AQ==\",\"AA==\",\"0g==\"]', datetime('now'), datetime('now'))")

    # Zone 1: mute=0xA4,0x05,0x06,0xFF,0x0B,0x18,0x02,0x01,0xD0 | unmute=0xA4,0x05,0x06,0xFF,0x0B,0x18,0x02,0x00,0xD1
    execute("INSERT INTO serial_commands (zone_index, mute, unmute, inserted_at, updated_at) VALUES (1, '[\"pA==\",\"BQ==\",\"Bg==\",\"/w==\",\"Cw==\",\"GA==\",\"Ag==\",\"AQ==\",\"0A==\"]', '[\"pA==\",\"BQ==\",\"Bg==\",\"/w==\",\"Cw==\",\"GA==\",\"Ag==\",\"AA==\",\"0Q==\"]', datetime('now'), datetime('now'))")

    # Zone 2: mute=0xA4,0x05,0x06,0xFF,0x0B,0x18,0x03,0x01,0xCF | unmute=0xA4,0x05,0x06,0xFF,0x0B,0x18,0x03,0x00,0xD0
    execute("INSERT INTO serial_commands (zone_index, mute, unmute, inserted_at, updated_at) VALUES (2, '[\"pA==\",\"BQ==\",\"Bg==\",\"/w==\",\"Cw==\",\"GA==\",\"Aw==\",\"AQ==\",\"zw==\"]', '[\"pA==\",\"BQ==\",\"Bg==\",\"/w==\",\"Cw==\",\"GA==\",\"Aw==\",\"AA==\",\"0A==\"]', datetime('now'), datetime('now'))")

    # Zone 3: mute=0xA4,0x05,0x06,0xFF,0x0B,0x18,0x04,0x01,0xCE | unmute=0xA4,0x05,0x06,0xFF,0x0B,0x18,0x04,0x00,0xCF
    execute("INSERT INTO serial_commands (zone_index, mute, unmute, inserted_at, updated_at) VALUES (3, '[\"pA==\",\"BQ==\",\"Bg==\",\"/w==\",\"Cw==\",\"GA==\",\"BA==\",\"AQ==\",\"zg==\"]', '[\"pA==\",\"BQ==\",\"Bg==\",\"/w==\",\"Cw==\",\"GA==\",\"BA==\",\"AA==\",\"zw==\"]', datetime('now'), datetime('now'))")

    # Zone 4: mute=0xA4,0x05,0x06,0xFF,0x0B,0x18,0x05,0x01,0xCD | unmute=0xA4,0x05,0x06,0xFF,0x0B,0x18,0x05,0x00,0xCE
    execute("INSERT INTO serial_commands (zone_index, mute, unmute, inserted_at, updated_at) VALUES (4, '[\"pA==\",\"BQ==\",\"Bg==\",\"/w==\",\"Cw==\",\"GA==\",\"BQ==\",\"AQ==\",\"zQ==\"]', '[\"pA==\",\"BQ==\",\"Bg==\",\"/w==\",\"Cw==\",\"GA==\",\"BQ==\",\"AA==\",\"zg==\"]', datetime('now'), datetime('now'))")

    # Zone 5: mute=0xA4,0x05,0x06,0xFF,0x0B,0x18,0x06,0x01,0xCC | unmute=0xA4,0x05,0x06,0xFF,0x0B,0x18,0x06,0x00,0xCD
    execute("INSERT INTO serial_commands (zone_index, mute, unmute, inserted_at, updated_at) VALUES (5, '[\"pA==\",\"BQ==\",\"Bg==\",\"/w==\",\"Cw==\",\"GA==\",\"Bg==\",\"AQ==\",\"zA==\"]', '[\"pA==\",\"BQ==\",\"Bg==\",\"/w==\",\"Cw==\",\"GA==\",\"Bg==\",\"AA==\",\"zQ==\"]', datetime('now'), datetime('now'))")

    # Zone 6: mute=0xA4,0x05,0x06,0xFF,0x0B,0x18,0x07,0x01,0xCB | unmute=0xA4,0x05,0x06,0xFF,0x0B,0x18,0x07,0x00,0xCC
    execute("INSERT INTO serial_commands (zone_index, mute, unmute, inserted_at, updated_at) VALUES (6, '[\"pA==\",\"BQ==\",\"Bg==\",\"/w==\",\"Cw==\",\"GA==\",\"Bw==\",\"AQ==\",\"yw==\"]', '[\"pA==\",\"BQ==\",\"Bg==\",\"/w==\",\"Cw==\",\"GA==\",\"Bw==\",\"AA==\",\"zA==\"]', datetime('now'), datetime('now'))")

    # Zone 7: mute=0xA4,0x05,0x06,0xFF,0x0B,0x18,0x08,0x01,0xCA | unmute=0xA4,0x05,0x06,0xFF,0x0B,0x18,0x08,0x00,0xCB
    execute("INSERT INTO serial_commands (zone_index, mute, unmute, inserted_at, updated_at) VALUES (7, '[\"pA==\",\"BQ==\",\"Bg==\",\"/w==\",\"Cw==\",\"GA==\",\"CA==\",\"AQ==\",\"yg==\"]', '[\"pA==\",\"BQ==\",\"Bg==\",\"/w==\",\"Cw==\",\"GA==\",\"CA==\",\"AA==\",\"yw==\"]', datetime('now'), datetime('now'))")
  end
end
