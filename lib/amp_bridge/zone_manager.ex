defmodule AmpBridge.ZoneManager do
  @moduledoc """
  ZoneManager handles volume control and zone state tracking for ELAN amplifiers.

  This module manages:
  - Current volume levels for each zone
  - Volume up/down command sending
  - Target volume calculation and command queuing
  - Zone state tracking
  """

  use GenServer
  require Logger

  # Volume encoding constants - can be moved to config later
  @volume_encoding_formulas %{
    1 => 218,
    2 => 217,
    3 => 216,
    4 => 215,
    5 => 214,
    6 => 213,
    7 => 212,
    8 => 211
  }

  # Mute command sequences - each value is an array of chunks to be sent
  @mute_sequences %{
    1 => [
      {<<0xA4>>, 0},
      {<<0x05>>, 0},
      {<<0x06>>, 0},
      {<<0xFF>>, 0},
      {<<0x0B>>, 0},
      {<<0x18>>, 0},
      {<<0x01>>, 0},
      {<<0x01>>, 0},
      {<<0xD1>>, 0}
    ],
    2 => [
      {<<0xA4>>, 0},
      {<<0x05>>, 0},
      {<<0x06>>, 0},
      {<<0xFF>>, 0},
      {<<0x0B>>, 0},
      {<<0x18>>, 0},
      {<<0x02>>, 0},
      {<<0x01>>, 0},
      {<<0xD0>>, 0}
    ],
    3 => [
      {<<0xA4>>, 0},
      {<<0x05>>, 0},
      {<<0x06>>, 0},
      {<<0xFF>>, 0},
      {<<0x0B>>, 0},
      {<<0x18>>, 0},
      {<<0x03>>, 0},
      {<<0x01>>, 0},
      {<<0xCF>>, 0}
    ],
    4 => [
      {<<0xA4>>, 0},
      {<<0x05>>, 0},
      {<<0x06>>, 0},
      {<<0xFF>>, 0},
      {<<0x0B>>, 0},
      {<<0x18>>, 0},
      {<<0x04>>, 0},
      {<<0x01>>, 0},
      {<<0xCE>>, 0}
    ],
    5 => [
      {<<0xA4>>, 0},
      {<<0x05>>, 0},
      {<<0x06>>, 0},
      {<<0xFF>>, 0},
      {<<0x0B>>, 0},
      {<<0x18>>, 0},
      {<<0x05>>, 0},
      {<<0x01>>, 0},
      {<<0xCD>>, 0}
    ],
    6 => [
      {<<0xA4>>, 0},
      {<<0x05>>, 0},
      {<<0x06>>, 0},
      {<<0xFF>>, 0},
      {<<0x0B>>, 0},
      {<<0x18>>, 0},
      {<<0x06>>, 0},
      {<<0x01>>, 0},
      {<<0xCC>>, 0}
    ],
    7 => [
      {<<0xA4>>, 0},
      {<<0x05>>, 0},
      {<<0x06>>, 0},
      {<<0xFF>>, 0},
      {<<0x0B>>, 0},
      {<<0x18>>, 0},
      {<<0x07>>, 0},
      {<<0x01>>, 0},
      {<<0xCB>>, 0}
    ],
    8 => [
      {<<0xA4>>, 0},
      {<<0x05>>, 0},
      {<<0x06>>, 0},
      {<<0xFF>>, 0},
      {<<0x0B>>, 0},
      {<<0x18>>, 0},
      {<<0x08>>, 0},
      {<<0x01>>, 0},
      {<<0xCA>>, 0}
    ]
  }

  # Unmute command sequences - each value is an array of chunks to be sent
  @unmute_sequences %{
    1 => [
      {<<0xA4>>, 0},
      {<<0x05>>, 0},
      {<<0x06>>, 0},
      {<<0xFF>>, 0},
      {<<0x0B>>, 0},
      {<<0x18>>, 0},
      {<<0x01>>, 0},
      {<<0x00>>, 0},
      {<<0xD2>>, 0}
    ],
    2 => [
      {<<0xA4>>, 0},
      {<<0x05>>, 0},
      {<<0x06>>, 0},
      {<<0xFF>>, 0},
      {<<0x0B>>, 0},
      {<<0x18>>, 0},
      {<<0x02>>, 0},
      {<<0x00>>, 0},
      {<<0xD1>>, 0}
    ],
    3 => [
      {<<0xA4>>, 0},
      {<<0x05>>, 0},
      {<<0x06>>, 0},
      {<<0xFF>>, 0},
      {<<0x0B>>, 0},
      {<<0x18>>, 0},
      {<<0x03>>, 0},
      {<<0x00>>, 0},
      {<<0xD0>>, 0}
    ],
    4 => [
      {<<0xA4>>, 0},
      {<<0x05>>, 0},
      {<<0x06>>, 0},
      {<<0xFF>>, 0},
      {<<0x0B>>, 0},
      {<<0x18>>, 0},
      {<<0x04>>, 0},
      {<<0x00>>, 0},
      {<<0xCF>>, 0}
    ],
    5 => [
      {<<0xA4>>, 0},
      {<<0x05>>, 0},
      {<<0x06>>, 0},
      {<<0xFF>>, 0},
      {<<0x0B>>, 0},
      {<<0x18>>, 0},
      {<<0x05>>, 0},
      {<<0x00>>, 0},
      {<<0xCE>>, 0}
    ],
    6 => [
      {<<0xA4>>, 0},
      {<<0x05>>, 0},
      {<<0x06>>, 0},
      {<<0xFF>>, 0},
      {<<0x0B>>, 0},
      {<<0x18>>, 0},
      {<<0x06>>, 0},
      {<<0x00>>, 0},
      {<<0xCD>>, 0}
    ],
    7 => [
      {<<0xA4>>, 0},
      {<<0x05>>, 0},
      {<<0x06>>, 0},
      {<<0xFF>>, 0},
      {<<0x0B>>, 0},
      {<<0x18>>, 0},
      {<<0x07>>, 0},
      {<<0x00>>, 0},
      {<<0xCC>>, 0}
    ],
    8 => [
      {<<0xA4>>, 0},
      {<<0x05>>, 0},
      {<<0x06>>, 0},
      {<<0xFF>>, 0},
      {<<0x0B>>, 0},
      {<<0x18>>, 0},
      {<<0x08>>, 0},
      {<<0x00>>, 0},
      {<<0xCB>>, 0}
    ]
  }

  # Source command sequences - each zone has an array of source command sequences
  # Index 0 = source 1, index 1 = source 2, etc.
  @source_sequences %{
    1 => [
      [
        {<<0xA4>>, 0},
        {<<0x05>>, 1},
        {<<0x06>>, 1},
        {<<0xFF>>, 1},
        {<<0x0B>>, 1},
        {<<0x13>>, 1},
        {<<0x01>>, 1},
        {<<0x01>>, 1},
        {<<0xD6>>, 0}
      ],
      [
        {<<0xA4>>, 0},
        {<<0x05>>, 1},
        {<<0x06>>, 1},
        {<<0xFF>>, 1},
        {<<0x0B>>, 1},
        {<<0x13>>, 1},
        {<<0x01>>, 1},
        {<<0x02>>, 1},
        {<<0xD5>>, 0}
      ]
    ],
    2 => [],
    3 => [],
    4 => [],
    5 => [],
    6 => [],
    7 => [],
    8 => []
  }

  # Volume command constants
  @volume_up_byte1 0x02
  @volume_down_byte1 0x31

  # Client API

  @doc """
  Start the ZoneManager
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get current volume for a zone
  """
  def get_zone_volume(zone) do
    GenServer.call(__MODULE__, {:get_zone_volume, zone})
  end

  @doc """
  Get all zone volumes
  """
  def get_all_zone_volumes do
    GenServer.call(__MODULE__, :get_all_zone_volumes)
  end

  @doc """
  Set target volume for a zone
  """
  def set_zone_volume(zone, target_volume) do
    GenServer.cast(__MODULE__, {:set_zone_volume, zone, target_volume})
  end

  @doc """
  Set volume for a specific zone to the given percentage.

  This is a synchronous call that directly sets the volume without going through
  the GenServer cast mechanism. Useful for direct volume control.

  ## Parameters
  - `zone`: The zone number (1 or 2)
  - `percentage`: The volume percentage (0-100)

  ## Examples
      iex> ZoneManager.set_volume(1, 50)
      :ok
  """
  def set_volume(zone, percentage) when is_integer(zone) and is_integer(percentage) do
    Logger.info("ZoneManager: Setting zone #{zone} to #{percentage}%")

    clamped_percentage = max(0, min(100, percentage))

    if check_adapter_connection() do
      create_and_send_volume_command(zone, clamped_percentage)
      :ok
    else
      {:error, :adapter_not_connected}
    end
  end

  def set_volume(zone, percentage) do
    Logger.error(
      "ZoneManager: Invalid parameters - zone: #{inspect(zone)}, percentage: #{inspect(percentage)}"
    )

    {:error, :invalid_parameters}
  end

  @doc """
  Send volume up command for a zone
  """
  def volume_up(zone) do
    Logger.info("ZoneManager: Volume up for zone #{zone}")

    if check_adapter_connection() do
      chunks = create_volume_up_command_chunks(zone)
      send_command_chunks(chunks, "volume up")
    end
  end

  @doc """
  Send volume down command for a zone
  """
  def volume_down(zone) do
    Logger.info("ZoneManager: Volume down for zone #{zone}")

    if check_adapter_connection() do
      chunks = create_volume_down_command_chunks(zone)
      send_command_chunks(chunks, "volume down")
    end
  end

  @doc """
  Send mute command for a zone
  """
  def mute_zone(zone) do
    Logger.info("ZoneManager: Muting zone #{zone}")

    if check_adapter_connection() do
      chunks = get_mute_command_chunks(zone)

      if length(chunks) > 0 do
        send_command_chunks(chunks, "mute")
      else
        Logger.warning("ZoneManager: No mute command defined for zone #{zone}")
      end
    end
  end

  @doc """
  Send unmute command for a zone
  """
  def unmute_zone(zone) do
    Logger.info("ZoneManager: Unmuting zone #{zone}")

    if check_adapter_connection() do
      chunks = get_unmute_command_chunks(zone)

      if length(chunks) > 0 do
        send_command_chunks(chunks, "unmute")
      else
        Logger.warning("ZoneManager: No unmute command defined for zone #{zone}")
      end
    end
  end

  @doc """
  Change source for a zone
  """
  def change_zone_source(zone, source_index) do
    Logger.info("ZoneManager: Changing zone #{zone} to source #{source_index}")

    if check_adapter_connection() do
      chunks = get_source_command_chunks(zone, source_index)

      if length(chunks) > 0 do
        send_command_chunks(chunks, "source change")
      else
        Logger.warning(
          "ZoneManager: No source command defined for zone #{zone}, source #{source_index}"
        )
      end
    end
  end

  @doc """
  Update zone volume from amplifier response
  """
  def update_zone_volume(zone, volume) do
    GenServer.cast(__MODULE__, {:update_zone_volume, zone, volume})
  end

  @doc """
  Reset zone volume to unknown state
  """
  def reset_zone_volume(zone) do
    GenServer.cast(__MODULE__, {:reset_zone_volume, zone})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("ZoneManager starting up")

    state = %{
      zone_volumes: %{
        1 => nil,
        2 => nil,
        3 => nil,
        4 => nil,
        5 => nil,
        6 => nil,
        7 => nil,
        8 => nil
      },
      pending_commands: %{},
      command_queue: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:get_zone_volume, zone}, _from, state) do
    volume = Map.get(state.zone_volumes, zone, nil)
    {:reply, volume, state}
  end

  @impl true
  def handle_call(:get_all_zone_volumes, _from, state) do
    {:reply, state.zone_volumes, state}
  end

  @impl true
  def handle_cast({:set_zone_volume, zone, target_volume}, state) do
    Logger.info("ZoneManager: Setting zone #{zone} to #{target_volume}%")

    clamped_percentage = max(0, min(100, target_volume))

    if check_adapter_connection() do
      create_and_send_volume_command(zone, clamped_percentage)

      new_volumes = Map.put(state.zone_volumes, zone, clamped_percentage)
      new_pending = Map.delete(state.pending_commands, zone)

      {:noreply, %{state | zone_volumes: new_volumes, pending_commands: new_pending}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:update_zone_volume, zone, volume}, state) do
    Logger.info("ZoneManager: Updating zone #{zone} volume to #{volume}%")

    new_volumes = Map.put(state.zone_volumes, zone, volume)

    # Check if we have a pending command for this zone
    pending_target = Map.get(state.pending_commands, zone)

    if pending_target do
      Logger.info(
        "ZoneManager: Zone #{zone} volume updated to #{volume}%, continuing to target #{pending_target}%"
      )

      # Remove from pending and continue to target
      new_pending = Map.delete(state.pending_commands, zone)

      send_volume_commands_to_target(zone, volume, pending_target, %{
        state
        | zone_volumes: new_volumes,
          pending_commands: new_pending
      })
    else
      {:noreply, %{state | zone_volumes: new_volumes}}
    end
  end

  @impl true
  def handle_cast({:reset_zone_volume, zone}, state) do
    Logger.info("ZoneManager: Resetting zone #{zone} volume to unknown")
    new_volumes = Map.put(state.zone_volumes, zone, nil)
    new_pending = Map.delete(state.pending_commands, zone)
    {:noreply, %{state | zone_volumes: new_volumes, pending_commands: new_pending}}
  end

  # Private Functions

  defp get_volume_encoding_formula(zone) do
    # Default to 217 if zone not found
    Map.get(@volume_encoding_formulas, zone, 217)
  end

  defp get_mute_command_chunks(zone) do
    # Get mute command chunks for the zone
    Map.get(@mute_sequences, zone, [])
  end

  defp get_unmute_command_chunks(zone) do
    # Get unmute command chunks for the zone
    Map.get(@unmute_sequences, zone, [])
  end

  defp get_source_command_chunks(zone, source_index) do
    # Get source command chunks for the zone and source index
    zone_sources = Map.get(@source_sequences, zone, [])
    Enum.at(zone_sources, source_index, [])
  end

  defp send_volume_commands_to_target(zone, current_volume, target_volume, state) do
    if current_volume == target_volume do
      Logger.info("ZoneManager: Zone #{zone} already at target volume #{target_volume}%")
      {:noreply, state}
    else
      commands_needed = target_volume - current_volume

      if commands_needed > 0 do
        Logger.info("ZoneManager: Sending #{commands_needed} volume up commands for zone #{zone}")
        send_multiple_volume_up_commands(zone, commands_needed)
      else
        Logger.info(
          "ZoneManager: Sending #{abs(commands_needed)} volume down commands for zone #{zone}"
        )

        send_multiple_volume_down_commands(zone, abs(commands_needed))
      end

      {:noreply, state}
    end
  end

  defp create_and_send_volume_command(zone, percentage) do
    Logger.info("ZoneManager: Setting zone #{zone} to #{percentage}%")

    if check_adapter_connection() do
      encoding_formula = get_volume_encoding_formula(zone)
      volume_byte1 = percentage
      volume_byte2 = encoding_formula - percentage
      command_bytes = [0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, zone, volume_byte1, volume_byte2]
      checksum = calculate_checksum(command_bytes)

      chunks = create_zone_specific_chunks(zone, volume_byte1, volume_byte2, checksum)
      send_command_chunks(chunks, "volume set")
    end
  end

  defp send_multiple_volume_up_commands(zone, count) do
    Enum.each(1..count, fn i ->
      volume_up(zone)

      if i < count do
        Process.sleep(50)
      end
    end)
  end

  defp send_multiple_volume_down_commands(zone, count) do
    Enum.each(1..count, fn i ->
      volume_down(zone)

      if i < count do
        Process.sleep(50)
      end
    end)
  end

  defp calculate_checksum(command_bytes) do
    sum = Enum.sum(command_bytes)
    Bitwise.bxor(Bitwise.band(sum, 0xFF), 0x52)
  end

  defp create_volume_up_command_chunks(zone) do
    encoding_formula = get_volume_encoding_formula(zone)
    volume_byte1 = @volume_up_byte1
    volume_byte2 = encoding_formula - zone
    command_bytes = [0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, zone, volume_byte1, volume_byte2]
    checksum = calculate_checksum(command_bytes)

    create_zone_specific_chunks(zone, volume_byte1, volume_byte2, checksum)
  end

  defp create_volume_down_command_chunks(zone) do
    encoding_formula = get_volume_encoding_formula(zone)
    volume_byte1 = @volume_down_byte1
    volume_byte2 = encoding_formula - zone
    command_bytes = [0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, zone, volume_byte1, volume_byte2]
    checksum = calculate_checksum(command_bytes)

    create_zone_specific_chunks(zone, volume_byte1, volume_byte2, checksum)
  end

  defp create_zone_specific_chunks(zone, volume_byte1, volume_byte2, checksum) do
    case zone do
      1 ->
        # Zone 1: Different chunking pattern
        # [A4 05] [06 FF] [0B] [10] [01] [volume_byte1 volume_byte2] [checksum]
        [
          {<<0xA4, 0x05>>, 0},
          {<<0x06, 0xFF>>, 1},
          {<<0x0B>>, 1},
          {<<0x10>>, 1},
          {<<0x01>>, 1},
          {<<volume_byte1, volume_byte2>>, 1},
          {<<checksum>>, 0}
        ]

      _ ->
        # Zone 2 and others: Original chunking pattern
        # [A4 05] [06 FF 0B] [10 zone] [volume_byte1 volume_byte2] [checksum]
        [
          {<<0xA4, 0x05>>, 0},
          {<<0x06, 0xFF, 0x0B>>, 1},
          {<<0x10, zone>>, 1},
          {<<volume_byte1, volume_byte2>>, 1},
          {<<checksum>>, 0}
        ]
    end
  end

  defp check_adapter_connection do
    connection_status = AmpBridge.SerialManager.get_connection_status()

    if connection_status.adapter_1.connected do
      true
    else
      Logger.error("ZoneManager: Adapter 1 not connected")
      false
    end
  end

  defp send_command_chunks(chunks, command_type) do
    Enum.with_index(chunks, 1)
    |> Enum.each(fn {{chunk_data, delay_ms}, chunk_index} ->
      case AmpBridge.SerialManager.send_command(:adapter_1, chunk_data) do
        :ok ->
          Logger.debug("ZoneManager: Sent #{command_type} chunk #{chunk_index}")

        {:error, reason} ->
          Logger.error(
            "ZoneManager: Failed to send #{command_type} chunk #{chunk_index}: #{reason}"
          )
      end

      if delay_ms > 0 do
        Process.sleep(delay_ms)
      end
    end)
  end
end
