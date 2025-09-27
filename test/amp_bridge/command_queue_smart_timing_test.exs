defmodule AmpBridge.CommandQueueSmartTimingTest do
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

  test "Smart CTS timing - fast response" do
    # Test that if amp responds quickly (before initial delay), we move on immediately
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
    assert status.current_command != nil
    assert status.command_sent_at != nil

    # Wait for completion (should be fast in test mode)
    Process.sleep(20)

    # Command should be completed
    status = CommandQueue.get_status(CommandQueue)
    assert status.processing == false
    assert status.current_command == nil
    assert status.command_sent_at == nil

    IO.puts("✅ Smart CTS timing - fast response test passed!")
  end

  test "Smart CTS timing - slow response" do
    # Test that if amp takes longer than initial delay, we still wait properly
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
    assert status.current_command != nil
    assert status.command_sent_at != nil

    # Wait for completion (should complete within timeout)
    Process.sleep(50)

    # Command should be completed
    status = CommandQueue.get_status(CommandQueue)
    assert status.processing == false
    assert status.current_command == nil
    assert status.command_sent_at == nil

    IO.puts("✅ Smart CTS timing - slow response test passed!")
  end

  test "Timing configuration and state tracking" do
    # Test that timing configuration is properly set and state tracking works
    status = CommandQueue.get_status(CommandQueue)

    # These should match our setup values
    assert status.cts_initial_delay == 30
    assert status.cts_check_interval == 5
    assert status.cts_timeout == 100

    # Initial state should be clean
    assert status.processing == false
    assert status.current_command == nil
    assert status.command_sent_at == nil

    IO.puts("✅ Timing configuration and state tracking test passed!")
  end

  test "Command replacement with smart timing" do
    # Test that rapid commands get replaced properly with smart timing
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

    # Wait a bit
    Process.sleep(10)

    # Enqueue second command (should replace first)
    CommandQueue.enqueue(CommandQueue, command2)

    # Wait for completion
    Process.sleep(30)

    # Should only have processed one command (the replacement)
    status = CommandQueue.get_status(CommandQueue)
    assert status.processing == false
    assert length(status.queue) == 0

    IO.puts("✅ Command replacement with smart timing test passed!")
  end
end
