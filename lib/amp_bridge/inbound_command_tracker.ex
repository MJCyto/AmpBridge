defmodule AmpBridge.InboundCommandTracker do
  @moduledoc """
  Matches learned controller commands in incoming serial traffic and mirrors
  the resulting state locally. It never sends serial commands.
  """

  use GenServer
  require Logger

  alias AmpBridge.{Devices, LearnedCommands, ZoneCommandProtocol}

  @device_id 1

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(AmpBridge.PubSub, "serial_data")
    {:ok, %{buffers: %{adapter_1: <<>>, adapter_2: <<>>}, commands: load_commands()}}
  end

  @impl true
  def handle_info({:serial_data, data, _decoded, %{adapter: adapter}}, state) do
    adapter = normalize_adapter(adapter)

    if controller_adapter() == adapter do
      buffer = Map.get(state.buffers, adapter, <<>>) <> data
      {matches, remainder} = match_commands(buffer, state.commands, 9)
      {calculated_events, remainder} = ZoneCommandProtocol.decode(remainder)

      if matches != [] or calculated_events != [] do
        Logger.warning(
          "Inbound tracker matched adapter=#{inspect(adapter)} bytes=#{Base.encode16(data)} " <>
            "learned=#{inspect(Enum.map(matches, &{&1.control_type, &1.zone, &1.source_index}))} " <>
            "calculated=#{inspect(calculated_events)}"
        )
      end

      Enum.each(matches, &apply_match/1)
      Enum.each(calculated_events, &apply_calculated_event/1)
      {:noreply, %{state | buffers: Map.put(state.buffers, adapter, remainder)}}
    else
      {:noreply, state}
    end
  end

  def handle_info(:refresh_commands, state), do: {:noreply, %{state | commands: load_commands()}}

  def handle_info(_message, state), do: {:noreply, state}

  defp controller_adapter do
    case Devices.get_device(@device_id) do
      %{adapter_1_role: "controller"} -> :adapter_1
      %{adapter_2_role: "controller"} -> :adapter_2
      _ -> nil
    end
  end

  defp normalize_adapter(:adapter_1), do: :adapter_1
  defp normalize_adapter(:adapter_2), do: :adapter_2
  defp normalize_adapter("adapter_1"), do: :adapter_1
  defp normalize_adapter("adapter_2"), do: :adapter_2
  defp normalize_adapter(_), do: nil

  @doc "Match complete learned command sequences in a serial buffer."
  def match_commands(buffer, commands, minimum_suffix \\ 0) do
    case find_match(buffer, commands) do
      nil ->
        {[], keep_suffix(buffer, commands, minimum_suffix)}

      {command, offset} ->
        end_offset = offset + byte_size(command.command_sequence)
        remainder = binary_part(buffer, end_offset, byte_size(buffer) - end_offset)
        {matches, remainder} = match_commands(remainder, commands, minimum_suffix)
        {[command | matches], remainder}
    end
  end

  defp find_match(buffer, commands) do
    Enum.find_value(commands, fn command ->
      sequence = command.command_sequence

      if is_binary(sequence) and byte_size(sequence) > 0 do
        case :binary.match(buffer, sequence) do
          {offset, _length} -> {command, offset}
          :nomatch -> nil
        end
      end
    end)
  end

  defp load_commands, do: LearnedCommands.list_commands_for_device(@device_id)

  defp keep_suffix(buffer, commands, minimum_suffix) do
    max_length =
      commands
      |> Enum.map(&byte_size(&1.command_sequence || <<>>))
      |> Enum.max(fn -> 1 end)
      |> Kernel.-(1)
      |> max(minimum_suffix)

    if byte_size(buffer) > max_length do
      binary_part(buffer, byte_size(buffer) - max_length, max_length)
    else
      buffer
    end
  end

  defp apply_match(
         %{control_type: "change_source", zone: zone, source_index: source_index} = command
       ) do
    case Devices.get_device(@device_id) do
      nil ->
        :ok

      device ->
        source_name = source_name(device.sources || %{}, source_index)

        if source_name do
          source_states = Map.put(device.source_states || %{}, to_string(zone), source_name)

          case Devices.update_device(device, %{source_states: source_states}) do
            {:ok, _device} ->
              LearnedCommands.mark_command_used(command)
              AmpBridge.MQTTClient.publish_all_zones()
              Logger.info("Mirrored learned source command: zone=#{zone} source=#{source_name}")

            {:error, reason} ->
              Logger.warning("Could not mirror source command state: #{inspect(reason)}")
          end
        end
    end
  end

  defp apply_match(%{control_type: control_type, zone: zone} = command)
       when control_type in ["set_volume", "volume_up", "volume_down"] do
    case Devices.get_device(@device_id) do
      nil ->
        :ok

      device ->
        current = Map.get(device.volume_states || %{}, to_string(zone), 0)

        volume =
          case control_type do
            "set_volume" -> command.volume_level
            "volume_up" -> min(current + 1, 100)
            "volume_down" -> max(current - 1, 0)
          end

        if is_integer(volume) do
          volume_states = Map.put(device.volume_states || %{}, to_string(zone), volume)

          case Devices.update_device(device, %{volume_states: volume_states}) do
            {:ok, _device} ->
              LearnedCommands.mark_command_used(command)
              AmpBridge.MQTTClient.publish_all_zones()
              Logger.info("Mirrored learned volume command: zone=#{zone} volume=#{volume}")

            {:error, reason} ->
              Logger.warning("Could not mirror volume command state: #{inspect(reason)}")
          end
        end
    end
  end

  defp apply_match(_command), do: :ok

  defp apply_calculated_event(%{type: :set_volume, zone: zone, value: volume}) do
    update_device_state(:volume_states, zone, volume, "volume")
  end

  defp apply_calculated_event(%{type: type, zone: zone}) when type in [:mute, :unmute] do
    update_device_state(:mute_states, zone, type == :mute, "mute")
  end

  defp update_device_state(field, zone, value, label) do
    case Devices.get_device(@device_id) do
      nil ->
        :ok

      device ->
        states = Map.put(Map.get(device, field) || %{}, to_string(zone), value)

        case Devices.update_device(device, %{field => states}) do
          {:ok, _device} ->
            AmpBridge.MQTTClient.publish_all_zones()

            Logger.info(
              "Mirrored calculated #{label} command: zone=#{zone} value=#{inspect(value)}"
            )

          {:error, reason} ->
            Logger.warning("Could not mirror calculated #{label} state: #{inspect(reason)}")
        end
    end
  end

  defp source_name(sources, source_index) when is_integer(source_index) do
    source = Map.get(sources, to_string(source_index)) || Map.get(sources, source_index)

    case source do
      %{"name" => name} when is_binary(name) -> name
      %{name: name} when is_binary(name) -> name
      name when is_binary(name) -> name
      _ -> nil
    end
  end

  defp source_name(_sources, _source_index), do: nil
end
