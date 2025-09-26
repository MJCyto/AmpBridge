defmodule AmpBridge.Repo.Migrations.AddVolumeStatesToAudioDevices do
  use Ecto.Migration

  def change do
    alter table(:audio_devices) do
      add :volume_states, :map, default: %{}
    end
  end
end
