defmodule AmpBridge.Devices do
  @moduledoc """
  The Devices context handles all device-related database operations.
  This module provides functions for managing audio devices in the database.
  """

  import Ecto.Query
  alias AmpBridge.Repo
  alias AmpBridge.AudioDevice

  # DATA FLOW EXPLANATION:
  # 1. LiveViews can call list_device_ids/0 to get list of IDs
  # 2. Components can call get_device!/1 with an ID to get full data
  # 3. This separation keeps LiveViews lightweight
  # 4. Components fetch only the data they need

  @doc """
  Returns a list of all devices.
  """
  def list_devices do
    Repo.all(AudioDevice)
  end

  @doc """
  Returns a list of all device IDs.
  This is called by LiveViews to get the list of devices to render.
  """
  def list_device_ids do
    # STEP 1: Query database for just the IDs
    # This is efficient - we don't fetch full device data here
    AudioDevice
    |> select([d], d.id)
    |> Repo.all()
  end

  @doc """
  Gets a single device by ID.
  This is called by components to get their specific device data.
  """
  def get_device!(id) do
    # STEP 2: Fetch full device data for a specific ID
    # This is called by each component individually
    Repo.get!(AudioDevice, id)
  end

  @doc """
  Gets a single device by ID, returns nil if not found.
  """
  def get_device(id) do
    Repo.get(AudioDevice, id)
  end

  @doc """
  Creates a device.
  """
  def create_device(attrs \\ %{}) do
    case %AudioDevice{}
         |> AudioDevice.changeset(attrs)
         |> Repo.insert() do
      {:ok, device} = result ->
        # Broadcast the new device to all subscribers
        Phoenix.PubSub.broadcast(
          AmpBridge.PubSub,
          "device_updates",
          {:device_created, device}
        )

        result

      error ->
        error
    end
  end

  @doc """
  Updates a device.
  """
  def update_device(%AudioDevice{} = device, attrs) do
    case device
         |> AudioDevice.changeset(attrs)
         |> Repo.update() do
      {:ok, updated_device} = result ->
        # Broadcast the update to all subscribers
        Phoenix.PubSub.broadcast(
          AmpBridge.PubSub,
          "device_updates",
          {:device_updated, updated_device}
        )

        result

      error ->
        error
    end
  end

  @doc """
  Deletes a device.
  """
  def delete_device(%AudioDevice{} = device) do
    case Repo.delete(device) do
      {:ok, deleted_device} = result ->
        # Broadcast the deletion to all subscribers
        Phoenix.PubSub.broadcast(
          AmpBridge.PubSub,
          "device_updates",
          {:device_deleted, deleted_device.id}
        )

        result

      error ->
        error
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking device changes.
  """
  def change_device(%AudioDevice{} = device, attrs \\ %{}) do
    AudioDevice.changeset(device, attrs)
  end
end
