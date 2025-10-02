defmodule AmpBridge.ZoneGroup do
  @moduledoc """
  ZoneGroup schema for managing groups of zones that can be controlled together.

  A zone group allows multiple zones to be controlled as a single logical unit.
  Each zone in a group can have:
  - A volume modifier (percentage) for proportional volume control
  - An order index for sequential command execution
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "zone_groups" do
    field(:name, :string)
    field(:description, :string)
    field(:is_active, :boolean, default: true)

    belongs_to(:audio_device, AmpBridge.AudioDevice)
    has_many(:zone_group_memberships, AmpBridge.ZoneGroupMembership, on_delete: :delete_all)
    has_many(:zones, through: [:zone_group_memberships, :zone_index])

    timestamps()
  end

  @doc false
  def changeset(zone_group, attrs) do
    zone_group
    |> cast(attrs, [:name, :description, :is_active, :audio_device_id])
    |> validate_required([:name, :audio_device_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 500)
    |> unique_constraint([:audio_device_id, :name])
  end
end
