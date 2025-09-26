defmodule AmpBridge.SerialRelay do
  @moduledoc """
  Serial Relay - Forwards data between two serial adapters bidirectionally.

  This module acts as a middleman, receiving data from one adapter and
  forwarding it to the other adapter while logging the relay activity.
  """

  use GenServer
  require Logger

  @adapter_1 :adapter_1
  @adapter_2 :adapter_2

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_relay do
    GenServer.call(__MODULE__, :start_relay, 1000)
  end

  def start_relay_with_status(adapter_1_connected, adapter_2_connected) do
    GenServer.call(__MODULE__, {:start_relay_with_status, adapter_1_connected, adapter_2_connected}, 1000)
  end

  def stop_relay do
    GenServer.call(__MODULE__, :stop_relay, 1000)
  end

  def relay_status do
    GenServer.call(__MODULE__, :relay_status, 1000)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      relay_active: false,
      adapter_1_connected: false,
      adapter_2_connected: false,
      relay_stats: %{
        adapter_1_to_2: 0,
        adapter_2_to_1: 0,
        total_relayed: 0
      }
    }

    # Subscribe to serial data updates
    Phoenix.PubSub.subscribe(AmpBridge.PubSub, "serial_data")

    {:ok, state}
  end

  @impl true
  def handle_call(:start_relay, _from, state) do
    if state.relay_active do
      {:reply, {:error, :already_active}, state}
    else
      # Check if both adapters are connected
      connection_status = AmpBridge.SerialManager.get_connection_status()

      if connection_status.adapter_1.connected and connection_status.adapter_2.connected do
        new_state = %{state | relay_active: true}
        Logger.info("Serial relay started - bridging Adapter 1 and Adapter 2")
        {:reply, :ok, new_state}
      else
        {:reply, {:error, :adapters_not_connected}, state}
      end
    end
  end

  @impl true
  def handle_call({:start_relay_with_status, adapter_1_connected, adapter_2_connected}, _from, state) do
    if state.relay_active do
      {:reply, {:error, :already_active}, state}
    else
      if adapter_1_connected and adapter_2_connected do
        new_state = %{state | relay_active: true}
        Logger.info("Serial relay started - bridging Adapter 1 and Adapter 2")
        {:reply, :ok, new_state}
      else
        {:reply, {:error, :adapters_not_connected}, state}
      end
    end
  end

  @impl true
  def handle_call(:stop_relay, _from, state) do
    new_state = %{state | relay_active: false}
    Logger.info("Serial relay stopped")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:relay_status, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info({:serial_data, data, _decoded, adapter_info}, state) do
    adapter = adapter_info.adapter

    Logger.info("SerialRelay: Received data from #{adapter}, relay_active: #{state.relay_active}")

    if state.relay_active do
      case adapter do
        @adapter_1 ->
          # Relay from adapter 1 to adapter 2
          Logger.info("SerialRelay: Relaying from adapter 1 to adapter 2")

          case AmpBridge.SerialManager.send_command(@adapter_2, data, log_command: false) do
            :ok ->
              new_stats = update_relay_stats(state.relay_stats, :adapter_1_to_2)
              new_state = %{state | relay_stats: new_stats}

              Logger.info(
                "Relayed #{byte_size(data)} bytes from Adapter 1 to Adapter 2: #{AmpBridge.SerialManager.format_hex(data)}"
              )

              {:noreply, new_state}

            {:error, reason} ->
              Logger.error("Failed to relay data from Adapter 1 to Adapter 2: #{reason}")
              {:noreply, state}
          end

        @adapter_2 ->
          # Relay from adapter 2 to adapter 1
          Logger.info("SerialRelay: Relaying from adapter 2 to adapter 1")

          case AmpBridge.SerialManager.send_command(@adapter_1, data, log_command: false) do
            :ok ->
              new_stats = update_relay_stats(state.relay_stats, :adapter_2_to_1)
              new_state = %{state | relay_stats: new_stats}

              Logger.info(
                "Relayed #{byte_size(data)} bytes from Adapter 2 to Adapter 1: #{AmpBridge.SerialManager.format_hex(data)}"
              )

              {:noreply, new_state}

            {:error, reason} ->
              Logger.error("Failed to relay data from Adapter 2 to Adapter 1: #{reason}")
              {:noreply, state}
          end

        _ ->
          Logger.warning("SerialRelay: Unknown adapter: #{adapter}")
          {:noreply, state}
      end
    else
      Logger.info("SerialRelay: Relay not active, ignoring data from #{adapter}")
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp update_relay_stats(stats, direction) do
    new_count = Map.get(stats, direction, 0) + 1
    new_total = stats.total_relayed + 1

    stats
    |> Map.put(direction, new_count)
    |> Map.put(:total_relayed, new_total)
  end
end
