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

  def init(_opts) do
    {:ok, %{adapter_1_connection: nil, adapter_2_connection: nil}}
  end

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

  def send_command(_adapter, _data, _opts \\ []) do
    :ok
  end

  def send_raw_data(_adapter, _data) do
    :ok
  end

  def get_connection_status do
    %{
      adapter_1: %{connected: false, device: nil, settings: nil},
      adapter_2: %{connected: false, device: nil, settings: nil}
    }
  end

  def check_cts_status(_adapter) do
    {:ok, true}  # Simulate CTS high in test mode
  end

  def get_adapter_color(_adapter) do
    "blue"
  end
end
