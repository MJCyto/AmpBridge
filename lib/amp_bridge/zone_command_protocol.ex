defmodule AmpBridge.ZoneCommandProtocol do
  @moduledoc "Pure encoding and decoding for calculated zone commands."

  @volume_encoding_formulas %{
    1 => 218,
    2 => 217,
    3 => 216,
    4 => 215,
    5 => 214,
    6 => 213,
    7 => 212,
    8 => 211
  }

  @header <<0xA4, 0x05, 0x06, 0xFF, 0x0B>>

  @spec volume_frame(1..8, 0..100) :: {:ok, binary()} | {:error, :invalid_parameters}
  def volume_frame(zone, percentage)
      when zone in 1..8 and percentage in 0..100 do
    complement = volume_complement(zone, percentage)
    body = @header <> <<0x10, zone, percentage, complement>>
    {:ok, body <> <<checksum(body)>>}
  end

  def volume_frame(_, _), do: {:error, :invalid_parameters}

  @spec decode(binary()) :: {[map()], binary()}
  def decode(buffer) when is_binary(buffer), do: do_decode(buffer, [])

  def volume_complement(zone, percentage),
    do: Map.fetch!(@volume_encoding_formulas, zone) - percentage

  def checksum(binary) when is_binary(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.sum()
    |> then(&Bitwise.bxor(Bitwise.band(&1, 0xFF), 0x52))
  end

  defp do_decode(<<>>, events), do: {Enum.reverse(events), <<>>}

  defp do_decode(buffer, events) do
    case :binary.match(buffer, @header) do
      :nomatch ->
        {Enum.reverse(events), keep_suffix(buffer)}

      {offset, _} when offset > 0 ->
        do_decode(binary_part(buffer, offset, byte_size(buffer) - offset), events)

      {0, _} ->
        decode_at(buffer, events)
    end
  end

  defp decode_at(buffer, events) do
    case buffer do
      <<@header, 0x10, _rest::binary>> when byte_size(buffer) < 9 ->
        {Enum.reverse(events), buffer}

      <<@header, 0x18, _rest::binary>> when byte_size(buffer) < 9 ->
        {Enum.reverse(events), buffer}

      _ when byte_size(buffer) < 7 ->
        {Enum.reverse(events), buffer}

      _ ->
        decode_complete(buffer, events)
    end
  end

  defp decode_complete(
         <<@header, 0x10, zone, value, complement, rest::binary>>,
         events
       )
       when zone in 1..8 do
    frame = @header <> <<0x10, zone, value, complement>>

    cond do
      complement != volume_complement(zone, value) ->
        do_decode(binary_part(frame <> rest, 1, byte_size(frame <> rest) - 1), events)

      rest == <<>> or starts_with_header_prefix?(rest) ->
        do_decode(rest, [%{type: :set_volume, zone: zone - 1, value: value} | events])

      :binary.first(rest) == checksum(frame) ->
        do_decode(binary_part(rest, 1, byte_size(rest) - 1), [
          %{type: :set_volume, zone: zone - 1, value: value} | events
        ])

      true ->
        do_decode(binary_part(frame <> rest, 1, byte_size(frame <> rest) - 1), events)
    end
  end

  defp decode_complete(
         buffer = <<@header, 0x10, zone, value, complement, check_byte, rest::binary>>,
         events
       ) do
    frame = @header <> <<0x10, zone, value, complement>>

    if zone in 1..8 and complement == volume_complement(zone, value) and
         check_byte == checksum(frame) do
      do_decode(rest, [%{type: :set_volume, zone: zone - 1, value: value} | events])
    else
      do_decode(binary_part(buffer, 1, byte_size(buffer) - 1), events)
    end
  end

  defp decode_complete(buffer = <<@header, 0x18, zone, state, check_byte, rest::binary>>, events)
       when state in [0, 1] do
    if zone in 1..8 and check_byte == mute_checksum(zone, state) do
      type = if state == 1, do: :mute, else: :unmute
      do_decode(rest, [%{type: type, zone: zone - 1} | events])
    else
      do_decode(binary_part(buffer, 1, byte_size(buffer) - 1), events)
    end
  end

  defp decode_complete(buffer, events),
    do: do_decode(binary_part(buffer, 1, byte_size(buffer) - 1), events)

  defp keep_suffix(buffer) when byte_size(buffer) > 9,
    do: binary_part(buffer, byte_size(buffer) - 9, 9)

  defp keep_suffix(buffer), do: buffer

  defp starts_with_header?(<<@header, _::binary>>), do: true
  defp starts_with_header?(_), do: false

  defp starts_with_header_prefix?(rest) do
    starts_with_header?(rest) or
      (byte_size(rest) < byte_size(@header) and
         binary_part(@header, 0, byte_size(rest)) == rest)
  end

  defp mute_checksum(zone, 1), do: 0xD2 - zone
  defp mute_checksum(zone, 0), do: 0xD3 - zone
end
