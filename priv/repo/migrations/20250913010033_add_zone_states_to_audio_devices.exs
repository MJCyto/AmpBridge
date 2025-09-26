defmodule AmpBridge.Repo.Migrations.AddZoneStatesToAudioDevices do
  use Ecto.Migration

  def change do
    alter table(:audio_devices) do
      add :mute_states, :map, default: %{}
      add :source_states, :map, default: %{}
    end
  end
end
