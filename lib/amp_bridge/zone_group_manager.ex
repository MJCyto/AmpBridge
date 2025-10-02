defmodule AmpBridge.ZoneGroupManager do
  @moduledoc """
  ZoneGroupManager handles group control operations for zone groups.

  This module manages:
  - Group volume control with percentage modifiers
  - Group mute control (all zones must be muted for group to appear muted)
  - Group source control (sets all zones to same source)
  - Sequential command execution with delays
  """

  use GenServer
  require Logger

  alias AmpBridge.ZoneGroups
  alias AmpBridge.ZoneManager
  alias AmpBridge.Devices
  alias AmpBridge.MQTTClient

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Set volume for all zones in a group with percentage modifiers.
  """
  def set_group_volume(group_id, target_volume) do
    GenServer.cast(__MODULE__, {:set_group_volume, group_id, target_volume})
  end

  @doc """
  Toggle mute for all zones in a group.
  """
  def toggle_group_mute(group_id) do
    GenServer.cast(__MODULE__, {:toggle_group_mute, group_id})
  end

  @doc """
  Set source for all zones in a group.
  """
  def set_group_source(group_id, source) do
    GenServer.cast(__MODULE__, {:set_group_source, group_id, source})
  end

  @doc """
  Get group state (volume, mute, source) based on individual zone states.
  """
  def get_group_state(group_id) do
    GenServer.call(__MODULE__, {:get_group_state, group_id})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("ZoneGroupManager starting up")
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:set_group_volume, group_id, target_volume}, state) do
    Logger.info("ZoneGroupManager: Setting group #{group_id} volume to #{target_volume}%")

    case ZoneGroups.get_zone_group(group_id) do
      nil ->
        Logger.warning("ZoneGroupManager: Group #{group_id} not found")
        {:noreply, state}

      _zone_group ->
        # Get zone memberships ordered by execution order
        memberships = ZoneGroups.get_group_zones(group_id)

        # Execute volume changes sequentially with 20ms delay
        Enum.with_index(memberships, fn membership, index ->
          # Get current volume of this zone
          device = Devices.get_device!(1)
          volume_states = device.volume_states || %{}
          current_volume = Map.get(volume_states, to_string(membership.zone_index), 50)

          # If base_volume is still the default (50), capture current volume as base
          base_volume = if membership.base_volume == 50 do
            Logger.info("ZoneGroupManager: Capturing current volume #{current_volume}% as base_volume for zone #{membership.zone_index}")
            # Update the membership with the current volume as base_volume
            ZoneGroups.update_zone_membership(group_id, membership.zone_index, %{base_volume: current_volume})
            current_volume
          else
            membership.base_volume
          end

          # Apply group volume as percentage of base volume
          # If group volume is 50%, set each zone to 50% of its base volume
          zone_target_volume = round(base_volume * (target_volume / 100))
          zone_target_volume = max(0, min(100, zone_target_volume)) # Clamp to 0-100

          Logger.info("ZoneGroupManager: Setting zone #{membership.zone_index} to #{zone_target_volume}% (group: #{target_volume}%, base: #{base_volume}%)")

          # Update zone volume in database and broadcast UI changes
          update_zone_volume_in_database(membership.zone_index, zone_target_volume)

          # Add delay between commands (except for the last one)
          if index < length(memberships) - 1 do
            Process.sleep(20)
          end
        end)

        # Publish MQTT update
        publish_group_mqtt_update(group_id)

        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:toggle_group_mute, group_id}, state) do
    Logger.info("ZoneGroupManager: Toggling group #{group_id} mute")

    case ZoneGroups.get_zone_group(group_id) do
      nil ->
        Logger.warning("ZoneGroupManager: Group #{group_id} not found")
        {:noreply, state}

      _zone_group ->
        # Get current mute state of all zones in group
        memberships = ZoneGroups.get_group_zones(group_id)

        # Check if all zones are muted (consistent with calculate_group_state)
        device = Devices.get_device!(1)
        mute_states = device.mute_states || %{}

        all_muted = Enum.all?(memberships, fn membership ->
          Map.get(mute_states, to_string(membership.zone_index), false)
        end)

        # Toggle all zones to opposite of current state
        new_mute_state = !all_muted

        # Execute mute commands sequentially with 20ms delay
        Enum.with_index(memberships, fn membership, index ->
          Logger.info("ZoneGroupManager: Setting zone #{membership.zone_index} mute to #{new_mute_state}")

          # Update zone mute state in database and broadcast UI changes
          update_zone_mute_in_database(membership.zone_index, new_mute_state)

          # Add delay between commands (except for the last one)
          if index < length(memberships) - 1 do
            Process.sleep(20)
          end
        end)

        # Publish MQTT update
        publish_group_mqtt_update(group_id)

        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:set_group_source, group_id, source}, state) do
    Logger.info("ZoneGroupManager: Setting group #{group_id} source to #{source}")

    case ZoneGroups.get_zone_group(group_id) do
      nil ->
        Logger.warning("ZoneGroupManager: Group #{group_id} not found")
        {:noreply, state}

      _zone_group ->
        # Get zone memberships ordered by execution order
        memberships = ZoneGroups.get_group_zones(group_id)

        # Parse source name to get 0-based index
        source_index = case source do
          "Off" -> nil
          source_name when is_binary(source_name) ->
            case Regex.run(~r/Source (\d+)/, source_name) do
              [_, index_str] -> String.to_integer(index_str) - 1
              nil -> nil
            end
          _ -> nil
        end

        # Execute source changes sequentially with 20ms delay
        Enum.with_index(memberships, fn membership, index ->
          Logger.info("ZoneGroupManager: Setting zone #{membership.zone_index} source to #{source} (index: #{source_index})")

          # Send source command to zone - handle "Off" vs "Source X" differently
          case source do
            "Off" ->
              # Use CommandLearner for turn_off (like individual zones do)
              case AmpBridge.CommandLearner.execute_command(1, "turn_off", membership.zone_index) do
                {:ok, :command_sent} ->
                  Logger.info("Turn off command sent successfully for zone #{membership.zone_index}")
                {:error, reason} ->
                  Logger.warning("Failed to send turn off command for zone #{membership.zone_index}: #{reason}")
              end
            _ when is_binary(source) ->
              # Use ZoneManager for source changes (when source_index is not nil)
              if source_index != nil do
                ZoneManager.change_zone_source(membership.zone_index + 1, source_index) # Convert to 1-based
              else
                Logger.warning("Could not parse source name: #{source}")
              end
          end

          # Update database with new source state
          update_zone_source_in_database(membership.zone_index, source)

          # Add delay between commands (except for the last one)
          if index < length(memberships) - 1 do
            Process.sleep(20)
          end
        end)

        # Publish MQTT update
        publish_group_mqtt_update(group_id)

        {:noreply, state}
    end
  end

  @impl true
  def handle_call({:get_group_state, group_id}, _from, state) do
    case ZoneGroups.get_zone_group(group_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _zone_group ->
        # Get zone memberships
        memberships = ZoneGroups.get_group_zones(group_id)

        # Get current states from database
        device = Devices.get_device!(1)
        mute_states = device.mute_states || %{}
        source_states = device.source_states || %{}
        volume_states = device.volume_states || %{}

        # Calculate group state
        group_state = calculate_group_state(memberships, mute_states, source_states, volume_states)

        {:reply, {:ok, group_state}, state}
    end
  end

  # Private functions

  defp calculate_group_state(memberships, mute_states, source_states, volume_states) do
    # Calculate mute state: group appears muted only if ALL zones are muted
    all_muted = Enum.all?(memberships, fn membership ->
      Map.get(mute_states, to_string(membership.zone_index), false)
    end)

    # Calculate source state: if all zones have same source, use it; otherwise show "(Mixed)"
    sources = Enum.map(memberships, fn membership ->
      Map.get(source_states, to_string(membership.zone_index), nil)
    end)

    source_state = case Enum.uniq(sources) do
      [nil] -> "Off"
      [source] when source != nil -> source
      _ -> "(Mixed)"
    end

    # Calculate volume state: use average of zone volumes (could be enhanced with modifiers)
    volumes = Enum.map(memberships, fn membership ->
      Map.get(volume_states, to_string(membership.zone_index), 50)
    end)

    avg_volume = if length(volumes) > 0 do
      round(Enum.sum(volumes) / length(volumes))
    else
      50
    end

    %{
      muted: all_muted,
      source: source_state,
      volume: avg_volume,
      zone_count: length(memberships)
    }
  end


  defp update_zone_source_in_database(zone_index, source) do
    try do
      device = Devices.get_device!(1)

      # Convert "Off" to nil for database storage
      stored_source = case source do
        "Off" -> nil
        source -> source
      end

      current_source_states = device.source_states || %{}
      updated_source_states = Map.put(current_source_states, to_string(zone_index), stored_source)

      case Devices.update_device(device, %{source_states: updated_source_states}) do
        {:ok, _updated_device} ->
          # Broadcast the change to the dashboard
          display_source = source || "Off"
          Phoenix.PubSub.broadcast(
            AmpBridge.PubSub,
            "device_updates",
            {:zone_source_changed, zone_index, display_source}
          )
          Logger.info("Updated zone #{zone_index} source to #{display_source} in database")

        {:error, changeset} ->
          Logger.error("Failed to update zone #{zone_index} source: #{inspect(changeset)}")
      end
    rescue
      error ->
        Logger.error("Failed to update zone source in database: #{inspect(error)}")
    end
  end

  defp publish_group_mqtt_update(group_id) do
    case ZoneGroups.get_zone_group(group_id) do
      nil ->
        Logger.warning("Group #{group_id} not found for MQTT update")

      group ->
        # Get zone memberships
        memberships = ZoneGroups.get_group_zones(group_id)

        # Get current states from database
        device = Devices.get_device!(1)
        mute_states = device.mute_states || %{}
        source_states = device.source_states || %{}
        volume_states = device.volume_states || %{}

        # Calculate group state
        group_state = calculate_group_state(memberships, mute_states, source_states, volume_states)

        MQTTClient.publish_group_state(group_id, Map.merge(group_state, %{
          name: group.name,
          description: group.description
        }))
    end
  end

  defp update_zone_mute_in_database(zone_index, muted) do
    try do
      device = Devices.get_device!(1)
      current_mute_states = device.mute_states || %{}
      updated_mute_states = Map.put(current_mute_states, to_string(zone_index), muted)

      case Devices.update_device(device, %{mute_states: updated_mute_states}) do
        {:ok, _updated_device} ->
          # Send the hardware command
          if muted do
            ZoneManager.mute_zone(zone_index + 1) # Convert to 1-based
          else
            ZoneManager.unmute_zone(zone_index + 1) # Convert to 1-based
          end

          # Broadcast the change to the dashboard
          Phoenix.PubSub.broadcast(
            AmpBridge.PubSub,
            "device_updates",
            {:zone_mute_changed, zone_index, muted}
          )
          Logger.info("Updated zone #{zone_index} mute to #{muted} in database")

        {:error, changeset} ->
          Logger.error("Failed to update zone #{zone_index} mute: #{inspect(changeset)}")
      end
    rescue
      error ->
        Logger.error("Failed to update zone mute in database: #{inspect(error)}")
    end
  end

  defp update_zone_volume_in_database(zone_index, volume) do
    try do
      device = Devices.get_device!(1)
      current_volume_states = device.volume_states || %{}
      updated_volume_states = Map.put(current_volume_states, to_string(zone_index), volume)

      case Devices.update_device(device, %{volume_states: updated_volume_states}) do
        {:ok, _updated_device} ->
          # Send the hardware command
          ZoneManager.set_zone_volume(zone_index + 1, volume) # Convert to 1-based

          # Broadcast the change to the dashboard
          Phoenix.PubSub.broadcast(
            AmpBridge.PubSub,
            "device_updates",
            {:zone_volume_changed, zone_index, volume}
          )
          Logger.info("Updated zone #{zone_index} volume to #{volume}% in database")

        {:error, changeset} ->
          Logger.error("Failed to update zone #{zone_index} volume: #{inspect(changeset)}")
      end
    rescue
      error ->
        Logger.error("Failed to update zone volume in database: #{inspect(error)}")
    end
  end
end
