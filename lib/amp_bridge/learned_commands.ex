defmodule AmpBridge.LearnedCommands do
  @moduledoc """
  Context for managing learned amplifier commands.
  """

  import Ecto.Query, warn: false
  alias AmpBridge.Repo
  alias AmpBridge.LearnedCommand

  @doc """
  Get all learned commands for a device.
  """
  def list_commands_for_device(device_id) do
    LearnedCommand
    |> where([c], c.device_id == ^device_id and c.is_active == true)
    |> order_by([c],
      desc: c.learned_at,
      asc: c.control_type,
      asc: c.zone,
      asc: c.source_index,
      asc: c.volume_level
    )
    |> Repo.all()
  end

  @doc """
  Get a specific learned command.
  """
  def get_command(device_id, control_type, zone, opts \\ []) do
    source_index = Keyword.get(opts, :source_index)
    volume_level = Keyword.get(opts, :volume_level)

    query =
      LearnedCommand
      |> where([c], c.device_id == ^device_id)
      |> where([c], c.control_type == ^control_type)
      |> where([c], c.zone == ^zone)
      |> where([c], c.is_active == true)

    query =
      if source_index do
        where(query, [c], c.source_index == ^source_index)
      else
        where(query, [c], is_nil(c.source_index))
      end

    query =
      if volume_level do
        where(query, [c], c.volume_level == ^volume_level)
      else
        where(query, [c], is_nil(c.volume_level))
      end

    Repo.one(query)
  end

  @doc """
  Create a new learned command.
  """
  def create_command(attrs) do
    %LearnedCommand{}
    |> LearnedCommand.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a learned command.
  """
  def update_command(learned_command, attrs) do
    learned_command
    |> LearnedCommand.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Mark a command as used (update last_used timestamp).
  """
  def mark_command_used(learned_command) do
    learned_command
    |> LearnedCommand.update_last_used_changeset()
    |> Repo.update()
  end

  @doc """
  Deactivate a learned command.
  """
  def deactivate_command(learned_command) do
    learned_command
    |> LearnedCommand.changeset(%{is_active: false})
    |> Repo.update()
  end

  @doc """
  Delete a learned command.
  """
  def delete_command(learned_command) do
    Repo.delete(learned_command)
  end

  @doc """
  Get commands by control type for a device.
  """
  def get_commands_by_type(device_id, control_type) do
    LearnedCommand
    |> where([c], c.device_id == ^device_id)
    |> where([c], c.control_type == ^control_type)
    |> where([c], c.is_active == true)
    |> order_by([c], [c.zone, c.source_index, c.volume_level])
    |> Repo.all()
  end

  @doc """
  Get all mute/unmute commands for a device.
  """
  def get_mute_commands(device_id) do
    LearnedCommand
    |> where([c], c.device_id == ^device_id)
    |> where([c], c.control_type in ["mute", "unmute"])
    |> where([c], c.is_active == true)
    |> order_by([c], [c.control_type, c.zone])
    |> Repo.all()
  end

  @doc """
  Get all volume commands for a device.
  """
  def get_volume_commands(device_id) do
    LearnedCommand
    |> where([c], c.device_id == ^device_id)
    |> where([c], c.control_type in ["volume_up", "volume_down", "set_volume"])
    |> where([c], c.is_active == true)
    |> order_by([c], [c.control_type, c.zone, c.volume_level])
    |> Repo.all()
  end

  @doc """
  Get all source change commands for a device.
  """
  def get_source_commands(device_id) do
    LearnedCommand
    |> where([c], c.device_id == ^device_id)
    |> where([c], c.control_type == "change_source")
    |> where([c], c.is_active == true)
    |> order_by([c], [c.zone, c.source_index])
    |> Repo.all()
  end

  @doc """
  Check if a command exists for a specific control action.
  """
  def command_exists?(device_id, control_type, zone, opts \\ []) do
    case get_command(device_id, control_type, zone, opts) do
      nil -> false
      _command -> true
    end
  end

  @doc """
  Get command sequence for a control action, with fallback to default.
  """
  def get_command_sequence(device_id, control_type, zone, opts \\ []) do
    case get_command(device_id, control_type, zone, opts) do
      nil ->
        # Fallback to default command from ZoneManager
        get_default_command_sequence(control_type, zone, opts)

      command ->
        # Mark as used and return learned command
        mark_command_used(command)
        command.command_sequence
    end
  end

  @doc """
  Get response pattern for a control action.
  """
  def get_response_pattern(device_id, control_type, zone, opts \\ []) do
    case get_command(device_id, control_type, zone, opts) do
      nil -> nil
      command -> command.response_pattern
    end
  end

  # Private function to get default command sequences
  # This will integrate with the existing ZoneManager commands
  defp get_default_command_sequence(control_type, zone, opts) do
    # This will be implemented to use existing hardcoded commands
    # from ZoneManager as fallbacks
    case control_type do
      "mute" -> get_default_mute_command(zone)
      "unmute" -> get_default_unmute_command(zone)
      "volume_up" -> get_default_volume_up_command(zone)
      "volume_down" -> get_default_volume_down_command(zone)
      "set_volume" -> get_default_set_volume_command(zone, Keyword.get(opts, :volume_level))
      "change_source" -> get_default_change_source_command(zone, Keyword.get(opts, :source_index))
      _ -> nil
    end
  end

  # Default command implementations - these will use existing ZoneManager logic
  defp get_default_mute_command(_zone) do
    # This will be implemented to return the hardcoded mute command for the zone
    # For now, return nil to indicate no default
    nil
  end

  defp get_default_unmute_command(_zone) do
    # This will be implemented to return the hardcoded unmute command for the zone
    nil
  end

  defp get_default_volume_up_command(_zone) do
    # This will be implemented to return the hardcoded volume up command for the zone
    nil
  end

  defp get_default_volume_down_command(_zone) do
    # This will be implemented to return the hardcoded volume down command for the zone
    nil
  end

  defp get_default_set_volume_command(_zone, _volume_level) do
    # This will be implemented to return the hardcoded set volume command for the zone
    nil
  end

  defp get_default_change_source_command(_zone, _source_index) do
    # This will be implemented to return the hardcoded change source command for the zone
    nil
  end
end
