#!/usr/bin/env elixir

# Test script for USB Device Scanner
# Run with: elixir test_usb_scanner.exs

# Start the application
Application.ensure_all_started(:amp_bridge)

# Test the USB device scanner
IO.puts("Testing USB Device Scanner...")

# Get available devices
devices = AmpBridge.USBDeviceScanner.get_devices()
IO.puts("Found #{length(devices)} USB devices:")

Enum.each(devices, fn device ->
  IO.puts("  - #{device.name} (#{device.type}) at #{device.path}")
  IO.puts("    Description: #{device.description}")
end)

# Test device assignment
amp_id = 1
IO.puts("\nTesting device assignment for amplifier #{amp_id}...")

if length(devices) > 0 do
  first_device = List.first(devices)
  IO.puts("Assigning #{first_device.path} to amplifier #{amp_id}...")

  case AmpBridge.USBDeviceScanner.assign_device_to_amp(first_device.path, amp_id) do
    {:ok, assigned_path} ->
      IO.puts("Successfully assigned #{assigned_path}")

      # Check the assignment
      assigned = AmpBridge.USBDeviceScanner.get_amp_device_assignment(amp_id)
      IO.puts("Current assignment: #{assigned}")

    {:error, reason} ->
      IO.puts("Failed to assign device: #{reason}")
  end
else
  IO.puts("No devices available to test assignment")
end

# Test re-scanning
IO.puts("\nTesting device re-scanning...")
new_devices = AmpBridge.USBDeviceScanner.rescan_devices()
IO.puts("Re-scan found #{length(new_devices)} devices")

IO.puts("\nTest completed!")
