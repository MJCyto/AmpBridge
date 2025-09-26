defmodule AmpBridge.Repo.Migrations.AddCommandLearningCompleteToAudioDevices do
  use Ecto.Migration

  def change do
    alter table(:audio_devices) do
      add(:command_learning_complete, :boolean, default: false)
    end
  end
end
