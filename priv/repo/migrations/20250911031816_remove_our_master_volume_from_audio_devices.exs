defmodule AmpBridge.Repo.Migrations.RemoveOurMasterVolumeFromAudioDevices do
  use Ecto.Migration

  def change do
    alter table(:audio_devices) do
      remove(:our_master_volume, :integer)
    end
  end
end
