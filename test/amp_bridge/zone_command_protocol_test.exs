defmodule AmpBridge.ZoneCommandProtocolTest do
  use ExUnit.Case, async: true

  alias AmpBridge.ZoneCommandProtocol

  test "decodes a calculated set-volume frame" do
    {:ok, frame} = ZoneCommandProtocol.volume_frame(1, 35)

    assert {[%{type: :set_volume, zone: 0, value: 35}], <<>>} =
             ZoneCommandProtocol.decode(frame)
  end

  test "decodes the controller's nine-byte volume frame" do
    assert ZoneCommandProtocol.decode(<<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, 0x01, 0x63, 0x77>>) ==
             {[%{type: :set_volume, zone: 0, value: 99}], <<>>}
  end

  test "decodes fragmented mute and unmute frames" do
    mute = <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x18, 0x01, 0x01, 0xD1>>
    unmute = <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x18, 0x01, 0x00, 0xD2>>

    {[], remainder} = ZoneCommandProtocol.decode(binary_part(mute, 0, 5))

    assert {[%{type: :mute, zone: 0}, %{type: :unmute, zone: 0}], <<>>} =
             ZoneCommandProtocol.decode(
               remainder <> binary_part(mute, 5, byte_size(mute) - 5) <> unmute
             )
  end

  test "decodes the captured mute frame when bytes arrive individually" do
    frame = <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x18, 0x01, 0x01, 0xD1>>

    {events, remainder} =
      Enum.reduce(:binary.bin_to_list(frame), {[], <<>>}, fn byte, {events, buffer} ->
        {new_events, new_buffer} = ZoneCommandProtocol.decode(buffer <> <<byte>>)
        {events ++ new_events, new_buffer}
      end)

    assert events == [%{type: :mute, zone: 0}]
    assert remainder == <<>>
  end

  test "rejects a frame with an invalid checksum" do
    {:ok, frame} = ZoneCommandProtocol.volume_frame(2, 40)
    <<prefix::binary-size(9), _checksum>> = frame

    assert {[], _remainder} = ZoneCommandProtocol.decode(prefix <> <<0>>)
  end

  test "uses the amplifier mute checksum values" do
    assert ZoneCommandProtocol.decode(<<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x18, 0x01, 0x01, 0xD1>>) ==
             {[%{type: :mute, zone: 0}], <<>>}

    assert ZoneCommandProtocol.decode(<<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x18, 0x01, 0x00, 0xD2>>) ==
             {[%{type: :unmute, zone: 0}], <<>>}
  end

  test "decodes captured controller volume and mute frames at every byte split" do
    frames = [
      <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x10, 0x01, 0x63, 0x77>>,
      <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x18, 0x01, 0x01, 0xD1>>,
      <<0xA4, 0x05, 0x06, 0xFF, 0x0B, 0x18, 0x01, 0x00, 0xD2>>
    ]

    expected = [
      %{type: :set_volume, zone: 0, value: 99},
      %{type: :mute, zone: 0},
      %{type: :unmute, zone: 0}
    ]

    input = IO.iodata_to_binary(frames)

    Enum.each(0..byte_size(input), fn split ->
      {first, second} = :erlang.split_binary(input, split)
      {events, remainder} = ZoneCommandProtocol.decode(first)
      {tail_events, final_remainder} = ZoneCommandProtocol.decode(remainder <> second)

      assert events ++ tail_events == expected
      assert final_remainder == <<>>
    end)
  end
end
