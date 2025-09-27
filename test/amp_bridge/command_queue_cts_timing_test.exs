defmodule AmpBridge.CommandQueueCTSTimingTest do
  use ExUnit.Case, async: false

  alias AmpBridge.CommandQueue

  setup do
    # Set test mode
    Application.put_env(:amp_bridge, :test_mode, true)

    # Start CommandQueue with custom timing
    {:ok, _} = CommandQueue.start_link([
      cts_initial_delay: 30,  # 30ms initial delay
      cts_check_interval: 5,  # 5ms check interval
      cts_timeout: 100        # 100ms timeout
    ])

    :ok
  end

  test "CTS timing flow control" do
    # Test the complete timing flow
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

    # Check initial state
    status = CommandQueue.get_status(CommandQueue)
    assert status.processing == true
    assert status.current_adapter == :adapter_1
    assert status.current_command != nil

    # Wait for initial delay + some CTS checks
    Process.sleep(50)  # Wait 50ms (initial delay + some checks)

    # Check that we're still processing (CTS should be simulated as high in test mode)
    status = CommandQueue.get_status(CommandQueue)
    assert status.processing == true

    # Wait a bit more for completion
    Process.sleep(20)

    # Command should be completed by now
    status = CommandQueue.get_status(CommandQueue)
    assert status.processing == false
    assert status.current_command == nil

    IO.puts("✅ CTS timing flow control test passed!")
  end

  test "Timing configuration" do
    # Test that timing configuration is properly set
    status = CommandQueue.get_status(CommandQueue)

    # These should match our setup values
    assert status.cts_initial_delay == 30
    assert status.cts_check_interval == 5
    assert status.cts_timeout == 100

    IO.puts("✅ Timing configuration test passed!")
  end

  test "Command replacement during timing" do
    # Test that rapid commands get replaced properly during timing
    command1 = %{
      id: "test_vol_0_30",
      type: :volume,
      zone: 0,
      params: %{volume: 30},
      data: <<0xA4, 0x05, 0x04>>,
      replaceable: true,
      priority: :normal
    }

    command2 = %{
      id: "test_vol_0_70",
      type: :volume,
      zone: 0,
      params: %{volume: 70},
      data: <<0xA4, 0x05, 0x08>>,
      replaceable: true,
      priority: :normal
    }

    # Enqueue first command
    CommandQueue.enqueue(CommandQueue, command1)
    CommandQueue.start_processing(CommandQueue, :adapter_1)

    # Wait for initial delay to start
    Process.sleep(10)

    # Enqueue second command (should replace first)
    CommandQueue.enqueue(CommandQueue, command2)

    # Wait for completion
    Process.sleep(50)

    # Should only have processed one command (the replacement)
    status = CommandQueue.get_status(CommandQueue)
    assert status.processing == false
    assert length(status.queue) == 0

    IO.puts("✅ Command replacement during timing test passed!")
  end
end
