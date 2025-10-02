defmodule AmpBridge.ZoneGroups do
  @moduledoc """
  The ZoneGroups context handles all zone group-related database operations.
  This module provides functions for managing zone groups and their memberships.
  """

  import Ecto.Query
  alias AmpBridge.Repo
  alias AmpBridge.ZoneGroup
  alias AmpBridge.ZoneGroupMembership
  alias AmpBridge.Devices

  @doc """
  Returns a list of all zone groups for a given audio device.
  """
  def list_zone_groups(audio_device_id) do
    ZoneGroup
    |> where([zg], zg.audio_device_id == ^audio_device_id)
    |> where([zg], zg.is_active == true)
    |> preload([:zone_group_memberships])
    |> Repo.all()
  end

  @doc """
  Gets a single zone group by ID.
  """
  def get_zone_group!(id) do
    ZoneGroup
    |> Repo.get!(id)
    |> Repo.preload(:zone_group_memberships)
  end

  @doc """
  Gets a single zone group by ID, returns nil if not found.
  """
  def get_zone_group(id) do
    case ZoneGroup
         |> Repo.get(id)
         |> Repo.preload(:zone_group_memberships) do
      nil -> nil
      zone_group -> zone_group
    end
  end

  @doc """
  Creates a zone group.
  """
  def create_zone_group(attrs \\ %{}) do
    %ZoneGroup{}
    |> ZoneGroup.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a zone group.
  """
  def update_zone_group(%ZoneGroup{} = zone_group, attrs) do
    zone_group
    |> ZoneGroup.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a zone group.
  """
  def delete_zone_group(%ZoneGroup{} = zone_group) do
    Repo.delete(zone_group)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking zone group changes.
  """
  def change_zone_group(%ZoneGroup{} = zone_group, attrs \\ %{}) do
    ZoneGroup.changeset(zone_group, attrs)
  end

  @doc """
  Adds a zone to a zone group.
  """
  def add_zone_to_group(zone_group_id, zone_index, attrs \\ %{}) do
    # Get current volume of the zone to use as base_volume
    device = Devices.get_device!(1)
    volume_states = device.volume_states || %{}
    current_volume = Map.get(volume_states, to_string(zone_index), 50) # Default to 50% if not found

    membership_attrs = Map.merge(%{
      zone_group_id: zone_group_id,
      zone_index: zone_index,
      base_volume: current_volume
    }, attrs)

    %ZoneGroupMembership{}
    |> ZoneGroupMembership.changeset(membership_attrs)
    |> Repo.insert()
  end

  @doc """
  Removes a zone from a zone group.
  """
  def remove_zone_from_group(zone_group_id, zone_index) do
    query = from(zgm in ZoneGroupMembership,
      where: zgm.zone_group_id == ^zone_group_id and zgm.zone_index == ^zone_index
    )

    case Repo.delete_all(query) do
      {1, _} -> :ok
      {0, _} -> {:error, :not_found}
    end
  end

  @doc """
  Updates a zone's membership in a group.
  """
  def update_zone_membership(zone_group_id, zone_index, attrs) do
    query = from(zgm in ZoneGroupMembership,
      where: zgm.zone_group_id == ^zone_group_id and zgm.zone_index == ^zone_index
    )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      membership ->
        membership
        |> ZoneGroupMembership.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Gets all zones that belong to a specific group.
  """
  def get_group_zones(zone_group_id) do
    ZoneGroupMembership
    |> where([zgm], zgm.zone_group_id == ^zone_group_id)
    |> Repo.all()
  end

  @doc """
  Gets all groups that contain a specific zone.
  """
  def get_zone_groups(zone_index) do
    ZoneGroup
    |> join(:inner, [zg], zgm in ZoneGroupMembership, on: zg.id == zgm.zone_group_id)
    |> where([zg, zgm], zgm.zone_index == ^zone_index)
    |> where([zg], zg.is_active == true)
    |> preload([:zone_group_memberships])
    |> Repo.all()
  end

  @doc """
  Creates a zone group with initial zone memberships.
  """
  def create_zone_group_with_zones(zone_group_attrs, zone_memberships \\ []) do
    Repo.transaction(fn ->
      case create_zone_group(zone_group_attrs) do
        {:ok, zone_group} ->
          # Add zone memberships
          Enum.each(zone_memberships, fn membership_attrs ->
            membership_attrs = Map.put(membership_attrs, :zone_group_id, zone_group.id)
            case add_zone_to_group(zone_group.id, membership_attrs[:zone_index], membership_attrs) do
              {:ok, _} -> :ok
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end)

          # Reload with memberships
          {:ok, get_zone_group!(zone_group.id)}

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

end
