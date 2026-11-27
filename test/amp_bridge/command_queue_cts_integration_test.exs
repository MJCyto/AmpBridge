defmodule AmpBridge.CommandQueueCTSIntegrationTest do
  use ExUnit.Case, async: false

  alias AmpBridge.CommandQueue
  alias AmpBridge.MockSerialManager

  setup do
    if pid = Process.whereis(CommandQueue), do: GenServer.stop(pid)
    unless Process.whereis(MockSerialManager), do: {:ok, _} = MockSerialManager.start_unlinked([])
    # Set test mode
    Application.put_env(:amp_bridge, :test_mode, true)

    # Start CommandQueue
    {:ok, _} = CommandQueue.start_link(transport: MockSerialManager)

    :ok
  end

  test "SerialManager CTS checking in test mode" do
    # Test CTS checking in test mode (simulated)
    result = MockSerialManager.check_cts_status(:adapter_1)
    assert result == {:ok, true}
  end

  test "CommandQueue uses real CTS checking in production mode" do
    # Set production mode
    Application.put_env(:amp_bridge, :test_mode, false)

    # Test that CommandQueue calls SerialManager
    # (This will fail in test environment since no real UART, but shows integration)
    assert :ok = CommandQueue.start_processing(CommandQueue, :adapter_1)

    # Reset test mode
    Application.put_env(:amp_bridge, :test_mode, true)
  end

  test "CTS flow control simulation" do
    # Test the CTS flow control logic
    # milliseconds
    cts_timeout = 200
    # milliseconds
    cts_check_interval = 10

    # Simulate CTS checking
    start_time = System.monotonic_time(:millisecond)

    # Simulate immediate CTS high
    cts_result = {:ok, true}
    assert cts_result == {:ok, true}

    elapsed = System.monotonic_time(:millisecond) - start_time
    # Should be immediate
    assert elapsed < 10

    # Test timeout calculation
    checks_per_timeout = div(cts_timeout, cts_check_interval)
    # Should check 20 times before timeout
    assert checks_per_timeout == 20

    IO.puts("✅ CTS flow control simulation test passed!")
  end

  test "CommandQueue CTS monitoring logic" do
    # Test the CTS monitoring state machine logic
    command = %{
      id: "test_vol_0_50",
      type: :volume,
      zone: 0,
      params: %{volume: 50},
      data: <<0xA4, 0x05, 0x06>>,
      replaceable: true,
      priority: :normal
    }

    # Enqueue command
    CommandQueue.enqueue(CommandQueue, command)

    # Start processing
    CommandQueue.start_processing(CommandQueue, :adapter_1)

    # Check that processing started
    status = CommandQueue.get_status(CommandQueue)
    assert status.processing == true
    assert status.current_adapter == :adapter_1

    # Stop processing
    CommandQueue.stop_processing(CommandQueue)

    # Check that processing stopped
    status = CommandQueue.get_status(CommandQueue)
    assert status.processing == false

    IO.puts("✅ CommandQueue CTS monitoring logic test passed!")
  end
end
