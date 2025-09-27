defmodule AmpBridge.CommandQueueBasicTest do
  use ExUnit.Case, async: false

  alias AmpBridge.CommandQueue
  alias AmpBridge.CommandQueue.Command

  setup do
    # Set test mode
    Application.put_env(:amp_bridge, :test_mode, true)

    # Start the MockSerialManager
    {:ok, _} = MockSerialManager.start_link()
    MockSerialManager.reset()

    # Start the CommandQueue process
    {:ok, pid} = CommandQueue.start_link()
    %{queue: pid}
  end

  describe "command queuing and replacement" do
    test "queues a single command", %{queue: queue} do
      command = %Command{
        id: "vol_1_50",
        type: :volume,
        zone: 1,
        params: %{volume: 50},
        data: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, 0x01, 0x32, 0xA8, 0xF6>>,
        replaceable: true
      }

      assert :ok = CommandQueue.enqueue(queue, command)
      assert [^command] = CommandQueue.get_queue(queue)
    end

    test "replaces replaceable commands for same zone and type", %{queue: queue} do
      # First command
      command1 = %Command{
        id: "vol_1_50",
        type: :volume,
        zone: 1,
        params: %{volume: 50},
        data: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, 0x01, 0x32, 0xA8, 0xF6>>,
        replaceable: true
      }

      # Second command that should replace the first
      command2 = %Command{
        id: "vol_1_75",
        type: :volume,
        zone: 1,
        params: %{volume: 75},
        data: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, 0x01, 0x4B, 0xA2, 0xF6>>,
        replaceable: true
      }

      assert :ok = CommandQueue.enqueue(queue, command1)
      assert :ok = CommandQueue.enqueue(queue, command2)

      # Should only have the second command
      assert [^command2] = CommandQueue.get_queue(queue)
    end

    test "does not replace non-replaceable commands", %{queue: queue} do
      command1 = %Command{
        id: "mute_1",
        type: :mute,
        zone: 1,
        params: %{muted: true},
        data: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x18, 0x01, 0x01, 0xD1>>,
        replaceable: false
      }

      command2 = %Command{
        id: "mute_1_again",
        type: :mute,
        zone: 1,
        params: %{muted: false},
        data: <<0xB4, 0x15, 0x16, 0x0F, 0x1B, 0x28, 0x11, 0x11, 0xE1>>,
        replaceable: false
      }

      assert :ok = CommandQueue.enqueue(queue, command1)
      assert :ok = CommandQueue.enqueue(queue, command2)

      # Should have both commands
      assert [^command2, ^command1] = CommandQueue.get_queue(queue)
    end

    test "does not replace commands for different zones", %{queue: queue} do
      command1 = %Command{
        id: "vol_1_50",
        type: :volume,
        zone: 1,
        params: %{volume: 50},
        data: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, 0x01, 0x32, 0xA8, 0xF6>>,
        replaceable: true
      }

      command2 = %Command{
        id: "vol_2_50",
        type: :volume,
        zone: 2,
        params: %{volume: 50},
        data: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, 0x02, 0x32, 0xA7, 0xF6>>,
        replaceable: true
      }

      assert :ok = CommandQueue.enqueue(queue, command1)
      assert :ok = CommandQueue.enqueue(queue, command2)

      # Should have both commands
      assert [^command2, ^command1] = CommandQueue.get_queue(queue)
    end

    test "does not replace commands of different types", %{queue: queue} do
      command1 = %Command{
        id: "vol_1_50",
        type: :volume,
        zone: 1,
        params: %{volume: 50},
        data: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, 0x01, 0x32, 0xA8, 0xF6>>,
        replaceable: true
      }

      command2 = %Command{
        id: "mute_1",
        type: :mute,
        zone: 1,
        params: %{muted: true},
        data: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x18, 0x01, 0x01, 0xD1>>,
        replaceable: true
      }

      assert :ok = CommandQueue.enqueue(queue, command1)
      assert :ok = CommandQueue.enqueue(queue, command2)

      # Should have both commands
      assert [^command2, ^command1] = CommandQueue.get_queue(queue)
    end
  end

  describe "command processing with CTS flow control" do
    test "processes commands in FIFO order", %{queue: queue} do
      # Set up mock to always succeed
      MockSerialManager.set_send_command_behavior(:always_ok)
      MockSerialManager.set_cts_status_behavior(:always_high)

      command1 = %Command{
        id: "vol_1_50",
        type: :volume,
        zone: 1,
        params: %{volume: 50},
        data: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, 0x01, 0x32, 0xA8, 0xF6>>,
        replaceable: true
      }

      command2 = %Command{
        id: "vol_2_75",
        type: :volume,
        zone: 2,
        params: %{volume: 75},
        data: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, 0x02, 0x4B, 0xA2, 0xF6>>,
        replaceable: true
      }

      assert :ok = CommandQueue.enqueue(queue, command1)
      assert :ok = CommandQueue.enqueue(queue, command2)

      # Start processing
      assert :ok = CommandQueue.start_processing(queue, :adapter_1)

      # Wait for processing to complete
      Process.sleep(100)

      # Verify commands were processed in order
      assert [] = CommandQueue.get_queue(queue)
    end

    test "waits for CTS to go high after sending command", %{queue: queue} do
      # Set up mock to delay CTS response
      MockSerialManager.set_send_command_behavior(:always_ok)
      MockSerialManager.set_cts_status_behavior(:high_after_delay)

      command = %Command{
        id: "vol_1_50",
        type: :volume,
        zone: 1,
        params: %{volume: 50},
        data: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, 0x01, 0x32, 0xA8, 0xF6>>,
        replaceable: true
      }

      assert :ok = CommandQueue.enqueue(queue, command)
      assert :ok = CommandQueue.start_processing(queue, :adapter_1)

      # Wait for processing to complete
      Process.sleep(200)

      assert [] = CommandQueue.get_queue(queue)
    end

    test "times out if CTS does not go high within timeout period", %{queue: queue} do
      # Set up mock to always return low CTS
      MockSerialManager.set_send_command_behavior(:always_ok)
      MockSerialManager.set_cts_status_behavior(:always_low)

      command = %Command{
        id: "vol_1_50",
        type: :volume,
        zone: 1,
        params: %{volume: 50},
        data: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, 0x01, 0x32, 0xA8, 0xF6>>,
        replaceable: true
      }

      assert :ok = CommandQueue.enqueue(queue, command)
      assert :ok = CommandQueue.start_processing(queue, :adapter_1)

      # Wait for timeout to occur
      Process.sleep(300)

      # Command should still be in queue due to timeout
      assert [^command] = CommandQueue.get_queue(queue)
    end

    test "handles serial communication errors gracefully", %{queue: queue} do
      # Set up mock to return error
      MockSerialManager.set_send_command_behavior(:always_error)
      MockSerialManager.set_cts_status_behavior(:always_high)

      command = %Command{
        id: "vol_1_50",
        type: :volume,
        zone: 1,
        params: %{volume: 50},
        data: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, 0x01, 0x32, 0xA8, 0xF6>>,
        replaceable: true
      }

      assert :ok = CommandQueue.enqueue(queue, command)
      assert :ok = CommandQueue.start_processing(queue, :adapter_1)

      # Wait for error handling
      Process.sleep(100)

      # Command should still be in queue due to error
      assert [^command] = CommandQueue.get_queue(queue)
    end
  end

  describe "queue management" do
    test "clears the queue", %{queue: queue} do
      command = %Command{
        id: "vol_1_50",
        type: :volume,
        zone: 1,
        params: %{volume: 50},
        data: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, 0x01, 0x32, 0xA8, 0xF6>>,
        replaceable: true
      }

      assert :ok = CommandQueue.enqueue(queue, command)
      assert [^command] = CommandQueue.get_queue(queue)

      assert :ok = CommandQueue.clear(queue)
      assert [] = CommandQueue.get_queue(queue)
    end

    test "gets queue status", %{queue: queue} do
      command1 = %Command{
        id: "vol_1_50",
        type: :volume,
        zone: 1,
        params: %{volume: 50},
        data: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, 0x01, 0x32, 0xA8, 0xF6>>,
        replaceable: true
      }

      command2 = %Command{
        id: "vol_2_75",
        type: :volume,
        zone: 2,
        params: %{volume: 75},
        data: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, 0x02, 0x4B, 0xA2, 0xF6>>,
        replaceable: true
      }

      assert :ok = CommandQueue.enqueue(queue, command1)
      assert :ok = CommandQueue.enqueue(queue, command2)

      status = CommandQueue.get_status(queue)
      assert status.queue_length == 2
      assert status.processing == false
      assert status.current_adapter == nil
    end

    test "stops processing", %{queue: queue} do
      command = %Command{
        id: "vol_1_50",
        type: :volume,
        zone: 1,
        params: %{volume: 50},
        data: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, 0x01, 0x32, 0xA8, 0xF6>>,
        replaceable: true
      }

      assert :ok = CommandQueue.enqueue(queue, command)
      assert :ok = CommandQueue.start_processing(queue, :adapter_1)
      assert :ok = CommandQueue.stop_processing(queue)

      status = CommandQueue.get_status(queue)
      assert status.processing == false
    end
  end

  describe "command priority and ordering" do
    test "processes high priority commands first", %{queue: queue} do
      low_priority = %Command{
        id: "vol_1_50",
        type: :volume,
        zone: 1,
        params: %{volume: 50},
        data: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, 0x01, 0x32, 0xA8, 0xF6>>,
        replaceable: true,
        priority: :low
      }

      high_priority = %Command{
        id: "mute_1",
        type: :mute,
        zone: 1,
        params: %{muted: true},
        data: <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x18, 0x01, 0x01, 0xD1>>,
        replaceable: false,
        priority: :high
      }

      # Add low priority first, then high priority
      assert :ok = CommandQueue.enqueue(queue, low_priority)
      assert :ok = CommandQueue.enqueue(queue, high_priority)

      # High priority should be processed first
      assert [^high_priority, ^low_priority] = CommandQueue.get_queue(queue)

      assert :ok = CommandQueue.start_processing(queue, :adapter_1)
      Process.sleep(100)

      assert [] = CommandQueue.get_queue(queue)
    end
  end
end
