defmodule AmpBridge.Repo.Migrations.AddInputsOutputsToAudioDevices do
  use Ecto.Migration

  def change do
    alter table(:audio_devices) do
      add(:inputs, :json, default: [])
      add(:outputs, :json, default: [])
    end
  end
end
