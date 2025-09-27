defmodule AmpBridge.ZoneManagerIntegrationTest do
  use ExUnit.Case, async: false

  alias AmpBridge.ZoneManager
  alias AmpBridge.CommandQueue

  setup do
    # Set test mode
    Application.put_env(:amp_bridge, :test_mode, true)

    # Start CommandQueue
    {:ok, _} = CommandQueue.start_link()

    # Start ZoneManager
    {:ok, _} = ZoneManager.start_link()

    :ok
  end

  test "ZoneManager set_volume uses CommandQueue" do
    # Test volume command
    result = ZoneManager.set_volume(1, 50)
    assert result == :ok

    # Check that command was queued
    queue = CommandQueue.get_queue(CommandQueue)
    assert length(queue) == 1

    command = hd(queue)
    assert command.type == :volume
    assert command.zone == 0  # 1-based zone converted to 0-based
    assert command.params.volume == 50
    assert command.replaceable == true
  end

  test "ZoneManager mute_zone uses CommandQueue" do
    # Test mute command
    result = ZoneManager.mute_zone(1)
    assert result == :ok

    # Check that command was queued
    queue = CommandQueue.get_queue(CommandQueue)
    assert length(queue) == 1

    command = hd(queue)
    assert command.type == :mute
    assert command.zone == 0  # 1-based zone converted to 0-based
    assert command.params.muted == true
    assert command.replaceable == false
    assert command.priority == :high
  end

  test "ZoneManager unmute_zone uses CommandQueue" do
    # Test unmute command
    result = ZoneManager.unmute_zone(1)
    assert result == :ok

    # Check that command was queued
    queue = CommandQueue.get_queue(CommandQueue)
    assert length(queue) == 1

    command = hd(queue)
    assert command.type == :mute
    assert command.zone == 0  # 1-based zone converted to 0-based
    assert command.params.muted == false
    assert command.replaceable == false
    assert command.priority == :high
  end

  test "ZoneManager change_zone_source uses CommandQueue" do
    # Test source change command
    result = ZoneManager.change_zone_source(1, 0)
    assert result == :ok

    # Check that command was queued
    queue = CommandQueue.get_queue(CommandQueue)
    assert length(queue) == 1

    command = hd(queue)
    assert command.type == :source
    assert command.zone == 0  # 1-based zone converted to 0-based
    assert command.params.source == 0
    assert command.replaceable == false
    assert command.priority == :normal
  end

  test "Volume command replacement works through ZoneManager" do
    # Send multiple volume commands for same zone
    ZoneManager.set_volume(1, 25)
    ZoneManager.set_volume(1, 50)
    ZoneManager.set_volume(1, 75)

    # Check that only the last command remains (replacement)
    queue = CommandQueue.get_queue(CommandQueue)
    assert length(queue) == 1

    command = hd(queue)
    assert command.params.volume == 75
  end

  test "Different zones don't replace each other" do
    # Send volume commands for different zones
    ZoneManager.set_volume(1, 50)
    ZoneManager.set_volume(2, 75)

    # Check that both commands remain
    queue = CommandQueue.get_queue(CommandQueue)
    assert length(queue) == 2

    # Check that both zones are represented
    zones = Enum.map(queue, & &1.zone)
    assert 0 in zones  # Zone 1 converted to 0
    assert 1 in zones  # Zone 2 converted to 1
  end

  test "Mixed command types are queued separately" do
    # Send different types of commands
    ZoneManager.set_volume(1, 50)
    ZoneManager.mute_zone(1)
    ZoneManager.change_zone_source(1, 0)

    # Check that all commands are queued
    queue = CommandQueue.get_queue(CommandQueue)
    assert length(queue) == 3

    # Check command types
    types = Enum.map(queue, & &1.type)
    assert :volume in types
    assert :mute in types
    assert :source in types
  end
end
