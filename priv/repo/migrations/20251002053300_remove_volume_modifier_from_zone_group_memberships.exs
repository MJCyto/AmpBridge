defmodule AmpBridge.Repo.Migrations.RemoveVolumeModifierFromZoneGroupMemberships do
  use Ecto.Migration

  def change do
    alter table(:zone_group_memberships) do
      remove :volume_modifier, :float
    end
  end
end
