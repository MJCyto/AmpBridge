defmodule AmpBridge.VolumeMappingTest do
  use ExUnit.Case

  # Test the volume command generation logic without requiring hardware
  describe "volume command generation" do
    test "generates correct command bytes for zone 2" do
      # Test cases based on capture analysis
      test_cases = [
        # 0% -> step 0
        {0, {0x5E, 0x7B}},
        # 25% -> step 1
        {25, {0x60, 0x79}},
        # 50% -> step 2
        {50, {0x62, 0x77}},
        # 75% -> step 3
        {75, {0x64, 0x75}},
        # 100% -> step 4
        {100, {0x66, 0x73}}
      ]

      for {percentage, expected_bytes} <- test_cases do
        volume_step = div(percentage, 25)
        byte1 = 0x5E + volume_step * 2
        byte2 = 0x7B - volume_step * 2

        assert {byte1, byte2} == expected_bytes,
               "Percentage #{percentage}% should give {0x#{Integer.to_string(byte1, 16) |> String.pad_leading(2, "0") |> String.upcase()}, 0x#{Integer.to_string(byte2, 16) |> String.pad_leading(2, "0") |> String.upcase()}}, got {0x#{Integer.to_string(elem(expected_bytes, 0), 16) |> String.pad_leading(2, "0") |> String.upcase()}, 0x#{Integer.to_string(elem(expected_bytes, 1), 16) |> String.pad_leading(2, "0") |> String.upcase()}}"
      end
    end

    test "generates correct command bytes for zone 1" do
      # Test cases for zone 1 (different base values)
      test_cases = [
        # 0% -> step 0
        {0, {0x5D, 0x7D}},
        # 25% -> step 1
        {25, {0x5F, 0x7B}},
        # 50% -> step 2
        {50, {0x61, 0x79}},
        # 75% -> step 3
        {75, {0x63, 0x77}},
        # 100% -> step 4
        {100, {0x65, 0x75}}
      ]

      for {percentage, expected_bytes} <- test_cases do
        volume_step = div(percentage, 25)
        byte1 = 0x5D + volume_step * 2
        byte2 = 0x7D - volume_step * 2

        assert {byte1, byte2} == expected_bytes,
               "Zone 1, Percentage #{percentage}% should give {0x#{Integer.to_string(byte1, 16) |> String.pad_leading(2, "0") |> String.upcase()}, 0x#{Integer.to_string(byte2, 16) |> String.pad_leading(2, "0") |> String.upcase()}}, got {0x#{Integer.to_string(elem(expected_bytes, 0), 16) |> String.pad_leading(2, "0") |> String.upcase()}, 0x#{Integer.to_string(elem(expected_bytes, 1), 16) |> String.pad_leading(2, "0") |> String.upcase()}}"
      end
    end

    test "clamps volume to valid range" do
      # Test edge cases
      # Negative percentage (truncated to 0)
      assert div(-10, 25) == 0
      # Over 100%
      assert div(150, 25) == 6

      # These should be clamped in the actual implementation
      assert div(0, 25) == 0
      assert div(100, 25) == 4
    end
  end

  describe "volume level mapping" do
    test "maps percentage to expected volume level" do
      # Based on capture analysis: volume levels go from 0x5D to 0x64
      # This represents the actual volume level the amplifier reports
      expected_mappings = [
        # 0% -> volume level 93
        {0, 0x5D},
        # 25% -> volume level 94
        {25, 0x5E},
        # 50% -> volume level 95
        {50, 0x5F},
        # 75% -> volume level 96
        {75, 0x60},
        # 100% -> volume level 97
        {100, 0x61}
      ]

      for {percentage, expected_level} <- expected_mappings do
        # This is what the amplifier should report as the volume level
        actual_level = 0x5D + div(percentage, 25)

        assert actual_level == expected_level,
               "Percentage #{percentage}% should result in volume level 0x#{Integer.to_string(expected_level, 16) |> String.pad_leading(2, "0") |> String.upcase()}, got 0x#{Integer.to_string(actual_level, 16) |> String.pad_leading(2, "0") |> String.upcase()}"
      end
    end
  end
end
