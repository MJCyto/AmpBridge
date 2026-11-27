defmodule AmpBridge.ZoneManagerIntegrationTest do
  use ExUnit.Case, async: false

  alias AmpBridge.ZoneManager
  alias AmpBridge.CommandQueue
  alias AmpBridge.SerialManager
  alias AmpBridge.TestSerialTransport

  setup do
    stop_if_running(CommandQueue)
    stop_if_running(SerialManager)
    stop_if_running(ZoneManager)
    unless Process.whereis(AmpBridge.Repo), do: {:ok, _} = AmpBridge.Repo.start_link()
    TestSerialTransport.reset()
    # Set test mode
    Application.put_env(:amp_bridge, :test_mode, true)

    # Start CommandQueue
    start_fresh(CommandQueue, transport: TestSerialTransport)
    start_fresh(SerialManager)
    TestSerialTransport.reset()

    # Start ZoneManager
    start_fresh(ZoneManager)

    :ok
  end

  defp start_fresh(module, opts \\ []) do
    case module.start_link(opts) do
      {:ok, _pid} ->
        :ok

      {:error, {:already_started, pid}} ->
        :ok = GenServer.stop(pid)
        Process.sleep(1)
        start_fresh(module, opts)
    end
  end

  defp stop_if_running(module) do
    if pid = Process.whereis(module) do
      try do
        GenServer.stop(pid)
      catch
        :exit, _ -> :ok
      end
    end
  end

  test "ZoneManager set_volume uses CommandQueue" do
    # Test volume command
    result = ZoneManager.set_volume(1, 50)
    assert result == :ok
    Process.sleep(50)

    assert [{_, command} | _] = TestSerialTransport.sent_commands()
    assert is_binary(command)
  end

  test "ZoneManager mute_zone uses CommandQueue" do
    # Test mute command
    result = ZoneManager.mute_zone(1)
    assert result == :ok
    Process.sleep(50)

    assert [{_, command} | _] = TestSerialTransport.sent_commands()
    assert is_binary(command)
  end

  test "ZoneManager unmute_zone uses CommandQueue" do
    # Test unmute command
    result = ZoneManager.unmute_zone(1)
    assert result == :ok
    Process.sleep(50)

    assert [{_, command} | _] = TestSerialTransport.sent_commands()
    assert is_binary(command)
  end

  test "ZoneManager change_zone_source uses CommandQueue" do
    # Test source change command
    result = ZoneManager.change_zone_source(1, 0)
    assert result == :ok
    Process.sleep(50)

    assert [{_, command} | _] = TestSerialTransport.sent_commands()
    assert is_binary(command)
  end

  test "Volume command replacement works through ZoneManager" do
    # Send multiple volume commands for same zone
    ZoneManager.set_volume(1, 25)
    ZoneManager.set_volume(1, 50)
    ZoneManager.set_volume(1, 75)
    Process.sleep(150)

    commands = TestSerialTransport.sent_commands()
    assert length(commands) >= 2
    assert Enum.any?(commands, fn {_adapter, data} -> 75 in :binary.bin_to_list(data) end)
  end

  test "Different zones don't replace each other" do
    # Send volume commands for different zones
    ZoneManager.set_volume(1, 50)
    ZoneManager.set_volume(2, 75)
    Process.sleep(150)

    assert length(TestSerialTransport.sent_commands()) == 2
  end

  test "Mixed command types are queued separately" do
    # Send different types of commands
    ZoneManager.set_volume(1, 50)
    ZoneManager.mute_zone(1)
    ZoneManager.change_zone_source(1, 0)
    Process.sleep(150)

    assert length(TestSerialTransport.sent_commands()) == 3
  end
end
