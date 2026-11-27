defmodule AmpBridge.MockSerialManager do
  @moduledoc """
  Mock Serial Manager for testing - avoids hardware connections
  """

  use GenServer
  require Logger

  def start_link(opts) do
    Logger.info("Starting Mock Serial Manager (test mode)")
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_unlinked(opts \\ []), do: GenServer.start(__MODULE__, opts, name: __MODULE__)

  def init(_opts) do
    {:ok,
     %{
       adapter_1_connection: nil,
       adapter_2_connection: nil,
       send_behavior: :always_ok,
       cts_behavior: :always_high,
       sent_commands: []
     }}
  end

  def reset, do: GenServer.call(__MODULE__, :reset)

  def set_send_command_behavior(behavior),
    do: GenServer.call(__MODULE__, {:send_behavior, behavior})

  def set_cts_status_behavior(behavior), do: GenServer.call(__MODULE__, {:cts_behavior, behavior})
  def sent_commands, do: GenServer.call(__MODULE__, :sent_commands)

  def get_available_devices do
    []
  end

  def set_adapter_settings(_adapter, _settings) do
    :ok
  end

  def connect_adapter(_adapter, _device_path) do
    :ok
  end

  def disconnect_adapter(_adapter) do
    :ok
  end

  def send_command(adapter, data, _opts \\ []),
    do: GenServer.call(__MODULE__, {:send_command, adapter, data})

  def send_raw_data(_adapter, _data) do
    :ok
  end

  def get_connection_status do
    %{
      adapter_1: %{connected: true, device: "test-adapter-1", settings: nil},
      adapter_2: %{connected: true, device: "test-adapter-2", settings: nil}
    }
  end

  def check_cts_status(_adapter), do: GenServer.call(__MODULE__, :check_cts)

  def get_adapter_color(_adapter) do
    "blue"
  end

  def handle_call(:reset, _from, _state),
    do:
      {:reply, :ok,
       %{
         adapter_1_connection: nil,
         adapter_2_connection: nil,
         send_behavior: :always_ok,
         cts_behavior: :always_high,
         sent_commands: []
       }}

  def handle_call({:send_behavior, behavior}, _from, state),
    do: {:reply, :ok, %{state | send_behavior: behavior}}

  def handle_call({:cts_behavior, behavior}, _from, state),
    do: {:reply, :ok, %{state | cts_behavior: behavior}}

  def handle_call(:send_command, _from, %{send_behavior: :always_ok} = state),
    do: {:reply, :ok, state}

  def handle_call({:send_command, adapter, data}, _from, %{send_behavior: :always_ok} = state),
    do: {:reply, :ok, %{state | sent_commands: [{adapter, data} | state.sent_commands]}}

  def handle_call(
        {:send_command, _adapter, _data},
        _from,
        %{send_behavior: :always_error} = state
      ),
      do: {:reply, {:error, :mock_failure}, %{state | sent_commands: state.sent_commands}}

  def handle_call(:send_command, _from, %{send_behavior: :always_error} = state),
    do: {:reply, {:error, :mock_failure}, state}

  def handle_call(:check_cts, _from, %{cts_behavior: :always_high} = state),
    do: {:reply, {:ok, true}, state}

  def handle_call(:check_cts, _from, %{cts_behavior: :always_low} = state),
    do: {:reply, {:ok, false}, state}

  def handle_call(:check_cts, _from, %{cts_behavior: :high_after_delay} = state),
    do: {:reply, {:ok, true}, state}

  def handle_call(:sent_commands, _from, state),
    do: {:reply, Enum.reverse(state.sent_commands), state}
end

defmodule AmpBridge.TestSerialTransport do
  @table :amp_bridge_test_serial_transport

  def reset do
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  def send_command(adapter, data) do
    ensure_table()
    :ets.insert(@table, {:command, adapter, data})
    :ok
  end

  def check_cts_status(_adapter), do: {:ok, true}

  def sent_commands do
    ensure_table()

    :ets.tab2list(@table)
    |> Enum.filter(&match?({:command, _, _}, &1))
    |> Enum.map(fn {:command, adapter, data} -> {adapter, data} end)
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, :bag])
      _ -> @table
    end
  end
end
