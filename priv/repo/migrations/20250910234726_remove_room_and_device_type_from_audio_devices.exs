defmodule AmpBridge.Repo.Migrations.RemoveRoomAndDeviceTypeFromAudioDevices do
  use Ecto.Migration

  def change do
    drop(index(:audio_devices, [:room]))
    drop(index(:audio_devices, [:device_type]))

    alter table(:audio_devices) do
      remove(:room, :string)
      remove(:device_type, :string)
    end
  end
end
