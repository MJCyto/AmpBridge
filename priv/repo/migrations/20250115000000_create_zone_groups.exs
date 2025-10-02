defmodule AmpBridge.Repo.Migrations.CreateZoneGroups do
  use Ecto.Migration

  def change do
    # Create zone_groups table
    create table(:zone_groups) do
      add(:name, :string, null: false)
      add(:description, :text)
      add(:audio_device_id, references(:audio_devices, on_delete: :delete_all), null: false)
      add(:is_active, :boolean, default: true)

      timestamps()
    end

    create(index(:zone_groups, [:audio_device_id]))
    create(index(:zone_groups, [:name]))
    create(unique_index(:zone_groups, [:audio_device_id, :name]))

    # Create zone_group_memberships table for many-to-many relationship
    create table(:zone_group_memberships) do
      add(:zone_group_id, references(:zone_groups, on_delete: :delete_all), null: false)
      add(:zone_index, :integer, null: false) # 0-based zone index
      add(:volume_modifier, :float, default: 1.0) # Percentage modifier for volume control
      add(:order_index, :integer, default: 0) # Order for sequential execution

      timestamps()
    end

    create(index(:zone_group_memberships, [:zone_group_id]))
    create(index(:zone_group_memberships, [:zone_index]))
    create(unique_index(:zone_group_memberships, [:zone_group_id, :zone_index]))
  end
end
