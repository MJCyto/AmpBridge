defmodule AmpBridge.Repo.Migrations.AddAutoDetectionCompleteToAudioDevices do
  use Ecto.Migration

  def change do
    alter table(:audio_devices) do
      # Auto-detection completion tracking
      add(:auto_detection_complete, :boolean, default: false)
      add(:adapter_1_name, :string)
      add(:adapter_2_name, :string)
      add(:adapter_1_role, :string)
      add(:adapter_2_role, :string)
    end
  end
end
