defmodule AmpBridge.Repo.Migrations.AddZonesAndSpeakerGroups do
  use Ecto.Migration

  def change do
    # Add zones and speaker groups as JSON fields
    alter table(:audio_devices) do
      add(:zones, :map, default: %{})
      add(:speaker_groups, :map, default: %{})
    end

    # Note: The channel_type and zone_id fields for outputs are already handled
    # by the embedded schema changes in the AudioDevice module
  end
end
