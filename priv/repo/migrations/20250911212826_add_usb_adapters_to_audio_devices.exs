defmodule AmpBridge.Repo.Migrations.AddUsbAdaptersToAudioDevices do
  use Ecto.Migration

  def change do
    alter table(:audio_devices) do
      # USB adapter assignments and settings
      add :adapter_1_device, :string
      add :adapter_1_settings, :map, default: %{}
      add :adapter_2_device, :string
      add :adapter_2_settings, :map, default: %{}
    end
  end
end
