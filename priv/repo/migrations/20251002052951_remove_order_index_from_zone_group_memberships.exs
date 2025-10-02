defmodule AmpBridge.Repo.Migrations.RemoveOrderIndexFromZoneGroupMemberships do
  use Ecto.Migration

  def change do
    alter table(:zone_group_memberships) do
      remove :order_index, :integer
    end
  end
end
