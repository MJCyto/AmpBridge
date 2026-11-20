defmodule AmpBridge.InboundCommandTrackerTest do
  use ExUnit.Case, async: true

  alias AmpBridge.InboundCommandTracker

  defp command(bytes) do
    %{command_sequence: bytes, control_type: "change_source", zone: 0, source_index: 2}
  end

  test "matches a learned command split across serial reads" do
    learned = command(<<0xAA, 0x02, 0xBB>>)

    {[], buffer} = InboundCommandTracker.match_commands(<<0xAA>>, [learned])
    {[matched], <<>>} = InboundCommandTracker.match_commands(buffer <> <<0x02, 0xBB>>, [learned])

    assert matched == learned
  end

  test "retains only the useful suffix when no command matches" do
    learned = command(<<0xAA, 0x02, 0xBB>>)

    {[], remainder} = InboundCommandTracker.match_commands(<<0x10, 0x11, 0xAA>>, [learned])

    assert remainder == <<0xAA>>
  end

  test "does not match empty command sequences" do
    assert {[], <<0xAA>>} = InboundCommandTracker.match_commands(<<0xAA>>, [command(<<>>)])
  end

  test "consumes multiple commands from one serial read" do
    first = command(<<0xAA, 0x01>>)
    second = command(<<0xBB, 0x02>>)

    {[first, second], <<>>} =
      InboundCommandTracker.match_commands(<<0xAA, 0x01, 0xBB, 0x02>>, [first, second])
  end
end
