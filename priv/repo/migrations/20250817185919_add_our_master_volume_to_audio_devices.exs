defmodule AmpBridge.Repo.Migrations.AddOurMasterVolumeToAudioDevices do
  use Ecto.Migration

  def change do
    alter table(:audio_devices) do
      add(:our_master_volume, :integer, default: 100)
    end
  end
end
