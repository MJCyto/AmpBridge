defmodule AmpBridge.MockUSBDeviceScanner do
  @moduledoc """
  Mock USB Device Scanner for testing - avoids hardware scanning
  """

  use GenServer
  require Logger

  def start_link(opts) do
    Logger.info("Starting Mock USB Device Scanner (test mode)")
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    {:ok, %{devices: []}}
  end

  def get_devices do
    []
  end

  def rescan_devices do
    :ok
  end

  def assign_device_to_amp(_device_path, _amp_id) do
    :ok
  end

  def unassign_device_from_amp(_amp_id) do
    :ok
  end

  def get_amp_device_assignment(_amp_id) do
    nil
  end
end
