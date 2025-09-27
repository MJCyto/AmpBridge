defmodule AmpBridge.MockHardwareManager do
  @moduledoc """
  Mock Hardware Manager for testing - avoids hardware scanning and connections
  """

  use GenServer
  require Logger

  def start_link(opts) do
    Logger.info("Starting Mock Hardware Manager (test mode)")
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    {:ok, %{}}
  end

  # Mock all the functions that the real HardwareManager would have
  def get_controllers do
    []
  end

  def get_controller_status(_id) do
    %{connected: false, device: nil}
  end
end
