#!/usr/bin/env elixir

# Hardware Manager Test Script
# This script demonstrates how the hardware manager responds to device updates

# Start the application if not already running
Application.ensure_all_started(:amp_bridge)

IO.puts("🔌 AmpBridge Hardware Manager Test")
IO.puts("===================================")
IO.puts("This test shows how the hardware manager responds to device updates")
IO.puts("")

# Get the hardware manager
hardware_manager = AmpBridge.HardwareManager

# List current amplifiers
IO.puts("📋 Current Amplifiers:")
amplifiers = hardware_manager.list_amplifiers()

Enum.each(amplifiers, fn amp ->
  IO.puts("  #{amp.name} (Device #{amp.device_id}) - Port: #{amp.serial_port}")
end)

IO.puts("")

# Get status of the main amplifier
IO.puts("📊 Main Amplifier Status:")

case hardware_manager.get_status(1) do
  {:ok, status} ->
    IO.puts("  Device ID: #{status.device_id}")
    IO.puts("  Name: #{status.name}")
    IO.puts("  Connected: #{status.is_connected}")
    IO.puts("  Error Count: #{status.error_count}")
    IO.puts("  Command Queue Length: #{status.command_queue_length}")
    IO.puts("")

  {:error, reason} ->
    IO.puts("  Error getting status: #{reason}")
    IO.puts("")
end

# Test sending a direct command
IO.puts("📡 Testing Direct Command:")

case hardware_manager.send_command(1, :master_volume, %{value: 50}) do
  {:ok, response} ->
    IO.puts("  ✅ Command sent successfully: #{response}")

  {:error, reason} ->
    IO.puts("  ❌ Command failed: #{reason}")
end

IO.puts("")

IO.puts("🎧 Hardware Manager is now monitoring device updates...")

IO.puts(
  "Make changes to volume controls in the web interface and watch the hardware manager respond!"
)

IO.puts("")
IO.puts("Press Ctrl+C to stop the test")
IO.puts("")

# Keep the main process alive
Process.sleep(:infinity)
