defmodule AmpBridge.Repo.Migrations.AddSourcesToAudioDevices do
  use Ecto.Migration

  def change do
    alter table(:audio_devices) do
      add(:sources, :map, default: %{})
    end
  end
end
