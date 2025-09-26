defmodule AmpBridge.Repo.Migrations.CreateAudioDevices do
  use Ecto.Migration

  def change do
    create table(:audio_devices) do
      add :name, :string, null: false
      add :device_type, :string, null: false
      add :room, :string
      add :ip_address, :string
      add :port, :integer
      add :is_active, :boolean, default: true
      add :settings, :map, default: %{}

      timestamps()
    end

    create index(:audio_devices, [:room])
    create index(:audio_devices, [:device_type])
    create index(:audio_devices, [:is_active])
  end
end
