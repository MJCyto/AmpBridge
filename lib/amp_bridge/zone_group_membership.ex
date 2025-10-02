defmodule AmpBridge.ZoneGroupMembership do
  @moduledoc """
  ZoneGroupMembership schema for the many-to-many relationship between
  zone groups and zones.

  Each membership defines:
  - volume_modifier: Percentage modifier for volume control (0.0 to 2.0)
  - order_index: Order for sequential command execution (0-based)
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "zone_group_memberships" do
    field(:zone_index, :integer) # 0-based zone index
    field(:base_volume, :integer, default: 50) # Base volume when zone was added to group

    belongs_to(:zone_group, AmpBridge.ZoneGroup)

    timestamps()
  end

  @doc false
  def changeset(zone_group_membership, attrs) do
    zone_group_membership
    |> cast(attrs, [:zone_group_id, :zone_index, :base_volume])
    |> validate_required([:zone_group_id, :zone_index])
    |> validate_inclusion(:zone_index, 0..7) # Support up to 8 zones (0-7)
    |> validate_inclusion(:base_volume, 0..100) # Base volume must be 0-100%
    |> unique_constraint([:zone_group_id, :zone_index])
  end
end
