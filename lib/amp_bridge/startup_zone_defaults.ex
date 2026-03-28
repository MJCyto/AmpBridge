defmodule AmpBridge.StartupZoneDefaults do
  @moduledoc false

  use GenServer
  require Logger

  alias AmpBridge.{CommandLearner, Devices}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  def normalized_off_unmuted_attrs(%{zones: zones} = device) when is_map(zones) and map_size(zones) > 0 do
    zone_keys =
      zones
      |> Map.keys()
      |> Enum.sort()

    base_sources = device.source_states || %{}

    source_states =
      Enum.reduce(zone_keys, base_sources, fn k, acc -> Map.put(acc, k, nil) end)

    base_mutes = device.mute_states || %{}
    mute_states = Enum.reduce(zone_keys, base_mutes, fn k, acc -> Map.put(acc, k, false) end)

    {:ok, %{source_states: source_states, mute_states: mute_states}}
  end

  def normalized_off_unmuted_attrs(_), do: :skip

  @impl true
  def init(_opts) do
    if Application.get_env(:amp_bridge, :mock_hardware, false) do
      {:ok, %{}}
    else
      run_boot()
      {:ok, %{}}
    end
  end

  defp run_boot do
    defaults = Application.get_env(:amp_bridge, __MODULE__, [])
    gap_ms = Keyword.get(defaults, :command_gap_ms, 50)
    device_config = Application.get_env(:amp_bridge, :device, [])
    device_id = Keyword.get(device_config, :default_device_id, 1)

    case Devices.get_device(device_id) do
      nil ->
        Logger.info("StartupZoneDefaults: no device #{device_id}, skipping")

      device ->
        case normalized_off_unmuted_attrs(device) do
          :skip ->
            Logger.info("StartupZoneDefaults: no zones configured, skipping")

          {:ok, attrs} ->
            case Devices.update_device(device, attrs) do
              {:ok, _} ->
                zone_keys = device.zones |> Map.keys() |> Enum.sort()

                Logger.info(
                  "StartupZoneDefaults: #{length(zone_keys)} zone(s) Off + unmuted in DB (volumes unchanged)"
                )

                zone_keys
                |> Enum.map(&String.to_integer/1)
                |> Enum.sort()
                |> push_turn_offs(device_id, gap_ms)

              {:error, changeset} ->
                Logger.warning("StartupZoneDefaults: DB update failed: #{inspect(changeset)}")
            end
        end
    end
  end

  defp push_turn_offs(sorted_zone_ids, device_id, gap_ms) do
    last_idx = length(sorted_zone_ids) - 1

    sorted_zone_ids
    |> Enum.with_index()
    |> Enum.each(fn {zid, idx} ->
      case CommandLearner.execute_command(device_id, "turn_off", zid) do
        {:ok, :command_sent} ->
          :ok

        nil ->
          Logger.debug("StartupZoneDefaults: no learned turn_off for zone #{zid}")

        {:error, reason} ->
          Logger.debug("StartupZoneDefaults: turn_off zone #{zid} error #{inspect(reason)}")

        other ->
          Logger.debug("StartupZoneDefaults: turn_off zone #{zid} -> #{inspect(other)}")
      end

      if idx < last_idx and gap_ms > 0, do: :timer.sleep(gap_ms)
    end)
  end
end
