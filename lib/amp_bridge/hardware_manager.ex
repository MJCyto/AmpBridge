defmodule AmpBridge.HardwareManager do
  @moduledoc """
  Hardware Manager - Responsible for controlling physical audio hardware via serial communication.

  This is a singleton process that manages all hardware controllers. Each controller is responsible
  for a specific amplifier and subscribes to device updates to send serial commands.

  Architecture:
  - HardwareManager (supervisor) - Manages all hardware controllers
  - HardwareController (worker) - Controls a specific amplifier
  - SerialCommandProcessor (worker) - Handles actual serial communication

  Future expansion:
  - Support for multiple amplifiers
  - Zone/speaker group management
  - Different communication protocols (RS232, RS485, TCP/IP)
  """

  use Supervisor
  require Logger

  @doc """
  Starts the hardware manager supervisor.
  This should only be started once per server instance.
  """
  def start_link(opts) do
    Logger.info("Starting Hardware Manager supervisor")
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Initializing Hardware Manager supervisor")

    children = [
      # Hardware Controller for the main amplifier
      {AmpBridge.HardwareController,
       %{
         device_id: 1,
         name: "Main Amplifier",
         # Serial port will be set by USB device assignment
         # serial_port: nil,  # Let USB scanner assign this
         baud_rate: 57600,
         data_bits: 8,
         stop_bits: 1,
         parity: :none
       }}

      # Future: Add more hardware controllers here
      # {AmpBridge.HardwareController, %{device_id: 2, name: "Zone 2 Amp", ...}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Sends a command to a specific amplifier.
  This is the main interface for other parts of the system.
  """
  def send_command(device_id, command_type, params) do
    Logger.info("Hardware Manager: Sending #{command_type} command to device #{device_id}")

    # Find the controller for this device
    case find_controller(device_id) do
      {:ok, controller_pid} ->
        GenServer.call(controller_pid, {:send_command, command_type, params})

      {:error, :not_found} ->
        Logger.warning("Hardware Manager: No controller found for device #{device_id}")
        {:error, :device_not_found}
    end
  end

  @doc """
  Gets the status of a specific amplifier.
  """
  def get_status(device_id) do
    case find_controller(device_id) do
      {:ok, controller_pid} ->
        GenServer.call(controller_pid, :get_status)

      {:error, :not_found} ->
        {:error, :device_not_found}
    end
  end

  @doc """
  Lists all managed amplifiers.
  """
  def list_amplifiers do
    # Get all child processes (controllers)
    children = Supervisor.which_children(__MODULE__)

    Enum.map(children, fn {_id, pid, _type, _modules} ->
      if Process.alive?(pid) do
        GenServer.call(pid, :get_info)
      end
    end)
    |> Enum.filter(&(&1 != nil))
  end

  # Private functions

  defp find_controller(device_id) do
    children = Supervisor.which_children(__MODULE__)

    case Enum.find(children, fn {_id, pid, _type, _modules} ->
           if Process.alive?(pid) do
             GenServer.call(pid, {:is_device, device_id})
           else
             false
           end
         end) do
      {_id, pid, _type, _modules} -> {:ok, pid}
      nil -> {:error, :not_found}
    end
  end
end
