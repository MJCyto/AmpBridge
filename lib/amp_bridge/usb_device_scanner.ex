defmodule AmpBridge.USBDeviceScanner do
  @moduledoc """
  USB Device Scanner - Scans for USB-to-serial devices and manages device assignments.

  This module:
  - Scans for available USB-to-serial devices on startup
  - Provides device list to the frontend
  - Manages device assignments to amplifiers
  - Allows re-scanning for new devices
  """

  use GenServer
  require Logger

  alias AmpBridge.Devices

  # Client API

  @doc """
  Starts the USB device scanner.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the list of available USB devices.
  """
  def get_devices do
    GenServer.call(__MODULE__, :get_devices)
  end

  @doc """
  Triggers a re-scan of USB devices.
  """
  def rescan_devices do
    GenServer.call(__MODULE__, :rescan_devices)
  end

  @doc """
  Assigns a USB device to an amplifier.
  """
  def assign_device_to_amp(device_path, amp_id) do
    GenServer.call(__MODULE__, {:assign_device_to_amp, device_path, amp_id})
  end

  @doc """
  Unassigns a USB device from an amplifier.
  """
  def unassign_device_from_amp(amp_id) do
    GenServer.call(__MODULE__, {:unassign_device_from_amp, amp_id})
  end

  @doc """
  Gets the device assignment for a specific amplifier.
  """
  def get_amp_device_assignment(amp_id) do
    GenServer.call(__MODULE__, {:get_amp_device_assignment, amp_id})
  end

  @doc """
  Checks if the system is properly initialized with all required components.
  """
  def is_system_initialized do
    GenServer.call(__MODULE__, :is_system_initialized)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("USB Device Scanner starting up")

    devices = scan_for_devices()

    state = %{
      devices: devices,
      amp_assignments: %{},
      last_scan: DateTime.utc_now()
    }

    Logger.info("USB Device Scanner initialized with #{length(devices)} devices")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_devices, _from, state) do
    {:reply, state.devices, state}
  end

  @impl true
  def handle_call(:rescan_devices, _from, state) do
    Logger.info("Re-scanning for USB devices")
    devices = scan_for_devices()

    new_state = %{state | devices: devices, last_scan: DateTime.utc_now()}

    Logger.info("Re-scan complete. Found #{length(devices)} devices")
    {:reply, devices, new_state}
  end

  @impl true
  def handle_call({:assign_device_to_amp, device_path, amp_id}, _from, state) do
    if device_path == "" do
      new_assignments = Map.delete(state.amp_assignments, amp_id)
      new_state = %{state | amp_assignments: new_assignments}

      Logger.info("Unassigned device from amplifier #{amp_id}")
      {:reply, {:ok, nil}, new_state}
    else
      if Enum.any?(state.devices, fn d -> d.path == device_path end) do
        new_assignments = Map.put(state.amp_assignments, amp_id, device_path)
        new_state = %{state | amp_assignments: new_assignments}

        Logger.info("Assigned device #{device_path} to amplifier #{amp_id}")
        {:reply, {:ok, device_path}, new_state}
      else
        {:reply, {:error, "Device not found"}, state}
      end
    end
  end

  @impl true
  def handle_call({:unassign_device_from_amp, amp_id}, _from, state) do
    new_assignments = Map.delete(state.amp_assignments, amp_id)
    new_state = %{state | amp_assignments: new_assignments}

    Logger.info("Unassigned device from amplifier #{amp_id}")
    {:reply, {:ok, nil}, new_state}
  end

  @impl true
  def handle_call({:get_amp_device_assignment, amp_id}, _from, state) do
    device_path = Map.get(state.amp_assignments, amp_id)
    {:reply, device_path, state}
  end

  @impl true
  def handle_call(:is_system_initialized, _from, state) do
    case Devices.get_device(1) do
      nil ->
        {:reply, false, state}

      device ->
        amp_1_assigned = !is_nil(device.adapter_1_device) && !is_nil(device.adapter_2_device)
        auto_detection_complete = device.auto_detection_complete == true
        command_learning_complete = device.command_learning_complete == true

        is_initialized = amp_1_assigned && auto_detection_complete && command_learning_complete
        {:reply, is_initialized, state}
    end
  end

  # Private functions

  defp scan_for_devices do
    device_patterns = [
      "/dev/ttyUSB*",
      "/dev/ttyACM*",
      "/dev/tty.usbserial-*",
      "/dev/tty.usbmodem*",
      "/dev/tty.SLAB_USBtoUART*",
      "/dev/tty.PL2303G-USBtoUART*",
      "/dev/tty.usb*",
      "/dev/tty.*USB*",
      "/dev/tty.*Serial*"
    ]

    devices =
      Enum.flat_map(device_patterns, fn pattern ->
        case Path.wildcard(pattern) do
          [] ->
            []

          paths ->
            Enum.map(paths, fn path ->
              %{
                path: path,
                name: Path.basename(path),
                type: get_device_type(path),
                description: get_device_description(path),
                available: true
              }
            end)
        end
      end)

    devices
    |> Enum.uniq_by(& &1.path)
    |> Enum.sort_by(& &1.name)
  end

  defp get_device_type(path) do
    cond do
      String.contains?(path, "ttyUSB") -> "USB Serial (FTDI/CP210x)"
      String.contains?(path, "ttyACM") -> "USB Serial (CDC-ACM)"
      String.contains?(path, "usbserial") -> "FTDI"
      String.contains?(path, "usbmodem") -> "USB Modem"
      String.contains?(path, "SLAB_USBtoUART") -> "Silicon Labs"
      String.contains?(path, "PL2303G-USBtoUART") -> "Prolific PL2303"
      String.contains?(path, "usb") -> "USB Serial"
      String.contains?(path, "USB") -> "USB Serial"
      String.contains?(path, "Serial") -> "USB Serial"
      true -> "Unknown"
    end
  end

  defp get_device_description(path) do
    cond do
      String.contains?(path, "ttyUSB") -> "USB Serial Device (FTDI/CP210x)"
      String.contains?(path, "ttyACM") -> "USB Serial Device (CDC-ACM)"
      String.contains?(path, "usbserial") -> "FTDI USB-to-Serial Converter"
      String.contains?(path, "usbmodem") -> "USB Modem Device"
      String.contains?(path, "SLAB_USBtoUART") -> "Silicon Labs USB-to-UART"
      String.contains?(path, "PL2303G-USBtoUART") -> "Prolific PL2303 USB-to-Serial Converter"
      String.contains?(path, "usb") -> "USB Serial Device"
      String.contains?(path, "USB") -> "USB Serial Device"
      String.contains?(path, "Serial") -> "USB Serial Device"
      true -> "Unknown USB Device"
    end
  end
end
