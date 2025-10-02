defmodule AmpBridge.Repo.Migrations.AddBaseVolumeToZoneGroupMemberships do
  use Ecto.Migration

  def change do
    alter table(:zone_group_memberships) do
      add :base_volume, :integer, default: 50, null: false
    end
  end
end
