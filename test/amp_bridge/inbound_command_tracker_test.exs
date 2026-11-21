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

  test "retains enough bytes for calculated frames after learned matching" do
    frame = <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x18, 0x01, 0x01, 0xD1>>

    {[], remainder} = InboundCommandTracker.match_commands(frame, [], 9)

    assert remainder == frame
  end

  test "replays source and calculated frames through the same stream boundary" do
    source = command(<<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x13, 0x01, 0x02, 0xD5>>)
    mute = <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x18, 0x01, 0x01, 0xD1>>

    {matches, remainder} =
      InboundCommandTracker.match_commands(source.command_sequence <> mute, [source], 9)

    {events, <<>>} = AmpBridge.ZoneCommandProtocol.decode(remainder)

    assert [matches] == [[source]]
    assert events == [%{type: :mute, zone: 0}]
  end
end
