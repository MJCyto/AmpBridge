defmodule AmpBridge.Repo.Migrations.CreateLearnedCommands do
  use Ecto.Migration

  def change do
    create table(:learned_commands) do
      add(:device_id, references(:audio_devices, on_delete: :delete_all), null: false)
      # "mute", "unmute", "volume_up", "volume_down", "set_volume", "change_source", "turn_off"
      add(:control_type, :string, null: false)
      add(:zone, :integer, null: false)
      # For source change commands
      add(:source_index, :integer)
      # For set_volume commands
      add(:volume_level, :integer)
      # The hex command to send
      add(:command_sequence, :binary, null: false)
      # The expected response pattern
      add(:response_pattern, :binary)
      add(:is_active, :boolean, default: true)
      add(:learned_at, :naive_datetime, null: false)
      add(:last_used, :naive_datetime)

      timestamps()
    end

    create(index(:learned_commands, [:device_id, :control_type, :zone]))
    create(index(:learned_commands, [:device_id, :is_active]))
    create(index(:learned_commands, [:control_type, :zone]))

    create(
      unique_index(
        :learned_commands,
        [:device_id, :control_type, :zone, :source_index, :volume_level],
        name: :unique_learned_command
      )
    )
  end
end
