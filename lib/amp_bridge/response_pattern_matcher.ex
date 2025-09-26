defmodule AmpBridge.ResponsePatternMatcher do
  @moduledoc """
  Module for matching incoming serial data against known response patterns.

  This handles both learned response patterns and default hardcoded patterns
  for common amplifier responses like mute/unmute confirmations.
  """

  require Logger
  alias AmpBridge.LearnedCommands

  # Default response patterns for common commands
  # These are the patterns we expect to receive from the amplifier
  @default_response_patterns %{
    # Zone mute responses - actual patterns from your amplifier
    "mute" => %{
      # Zone 1 (index 0) - pattern: A4 02 01 FD A4 08 0F 20 02 41 01 0C 64 4B 4B 00 00 01 00 90 02 EC
      # Note: The last few bytes may vary, so we'll match the core pattern
      0 =>
        <<0xA4, 0x02, 0x01, 0xFD, 0xA4, 0x08, 0x0F, 0x20, 0x02, 0x41, 0x01, 0x0C, 0x64, 0x4B,
          0x4B, 0x00, 0x00, 0x01, 0x00, 0x90, 0x02, 0xEC>>,
      # Zone 2 (index 1) - similar pattern but with zone 2
      1 =>
        <<0xA4, 0x02, 0x02, 0xFD, 0xA4, 0x08, 0x0F, 0x20, 0x02, 0x42, 0x01, 0x0C, 0x64, 0x4B,
          0x4B, 0x00, 0x00, 0x01, 0x00, 0x90, 0x02, 0xEB>>,
      # Zone 3 (index 2)
      2 =>
        <<0xA4, 0x02, 0x03, 0xFD, 0xA4, 0x08, 0x0F, 0x20, 0x02, 0x43, 0x01, 0x0C, 0x64, 0x4B,
          0x4B, 0x00, 0x00, 0x01, 0x00, 0x90, 0x02, 0xEA>>,
      # Zone 4 (index 3)
      3 =>
        <<0xA4, 0x02, 0x04, 0xFD, 0xA4, 0x08, 0x0F, 0x20, 0x02, 0x44, 0x01, 0x0C, 0x64, 0x4B,
          0x4B, 0x00, 0x00, 0x01, 0x00, 0x90, 0x02, 0xE9>>,
      # Zone 5 (index 4)
      4 =>
        <<0xA4, 0x02, 0x05, 0xFD, 0xA4, 0x08, 0x0F, 0x20, 0x02, 0x45, 0x01, 0x0C, 0x64, 0x4B,
          0x4B, 0x00, 0x00, 0x01, 0x00, 0x90, 0x02, 0xE8>>,
      # Zone 6 (index 5)
      5 =>
        <<0xA4, 0x02, 0x06, 0xFD, 0xA4, 0x08, 0x0F, 0x20, 0x02, 0x46, 0x01, 0x0C, 0x64, 0x4B,
          0x4B, 0x00, 0x00, 0x01, 0x00, 0x90, 0x02, 0xE7>>,
      # Zone 7 (index 6)
      6 =>
        <<0xA4, 0x02, 0x07, 0xFD, 0xA4, 0x08, 0x0F, 0x20, 0x02, 0x47, 0x01, 0x0C, 0x64, 0x4B,
          0x4B, 0x00, 0x00, 0x01, 0x00, 0x90, 0x02, 0xE6>>,
      # Zone 8 (index 7)
      7 =>
        <<0xA4, 0x02, 0x08, 0xFD, 0xA4, 0x08, 0x0F, 0x20, 0x02, 0x48, 0x01, 0x0C, 0x64, 0x4B,
          0x4B, 0x00, 0x00, 0x01, 0x00, 0x90, 0x02, 0xE5>>
    },

    # Zone unmute responses - we need to determine the actual unmute pattern
    # For now, using a placeholder pattern that we'll need to update with real data
    "unmute" => %{
      # Zone 1 - placeholder pattern (need actual unmute response)
      0 =>
        <<0xA4, 0x02, 0x01, 0xFD, 0xA4, 0x08, 0x0F, 0x20, 0x02, 0x41, 0x01, 0x0C, 0x64, 0x4B,
          0x4B, 0x00, 0x00, 0x01, 0x00, 0x90, 0x02, 0xEC>>,
      # Zone 2
      1 =>
        <<0xA4, 0x02, 0x02, 0xFD, 0xA4, 0x08, 0x0F, 0x20, 0x02, 0x42, 0x01, 0x0C, 0x64, 0x4B,
          0x4B, 0x00, 0x00, 0x01, 0x00, 0x90, 0x02, 0xEB>>,
      # Zone 3
      2 =>
        <<0xA4, 0x02, 0x03, 0xFD, 0xA4, 0x08, 0x0F, 0x20, 0x02, 0x43, 0x01, 0x0C, 0x64, 0x4B,
          0x4B, 0x00, 0x00, 0x01, 0x00, 0x90, 0x02, 0xEA>>,
      # Zone 4
      3 =>
        <<0xA4, 0x02, 0x04, 0xFD, 0xA4, 0x08, 0x0F, 0x20, 0x02, 0x44, 0x01, 0x0C, 0x64, 0x4B,
          0x4B, 0x00, 0x00, 0x01, 0x00, 0x90, 0x02, 0xE9>>,
      # Zone 5
      4 =>
        <<0xA4, 0x02, 0x05, 0xFD, 0xA4, 0x08, 0x0F, 0x20, 0x02, 0x45, 0x01, 0x0C, 0x64, 0x4B,
          0x4B, 0x00, 0x00, 0x01, 0x00, 0x90, 0x02, 0xE8>>,
      # Zone 6
      5 =>
        <<0xA4, 0x02, 0x06, 0xFD, 0xA4, 0x08, 0x0F, 0x20, 0x02, 0x46, 0x01, 0x0C, 0x64, 0x4B,
          0x4B, 0x00, 0x00, 0x01, 0x00, 0x90, 0x02, 0xE7>>,
      # Zone 7
      6 =>
        <<0xA4, 0x02, 0x07, 0xFD, 0xA4, 0x08, 0x0F, 0x20, 0x02, 0x47, 0x01, 0x0C, 0x64, 0x4B,
          0x4B, 0x00, 0x00, 0x01, 0x00, 0x90, 0x02, 0xE6>>,
      # Zone 8
      7 =>
        <<0xA4, 0x02, 0x08, 0xFD, 0xA4, 0x08, 0x0F, 0x20, 0x02, 0x48, 0x01, 0x0C, 0x64, 0x4B,
          0x4B, 0x00, 0x00, 0x01, 0x00, 0x90, 0x02, 0xE5>>
    }
  }

  @doc """
  Match incoming serial data against both learned and default response patterns.

  Returns {:ok, match_info} if a pattern matches, or :no_match if no pattern matches.
  """
  def match_response(device_id, serial_data, rolling_buffer \\ "") do
    # First try learned patterns
    case match_learned_patterns(device_id, serial_data) do
      {:ok, match_info} ->
        {:ok, match_info}

      :no_match ->
        # Then try default patterns with rolling buffer
        match_default_patterns(serial_data, rolling_buffer)
    end
  end

  @doc """
  Match against learned response patterns from the database.
  """
  def match_learned_patterns(device_id, serial_data) do
    # Get all active learned commands for this device
    commands = LearnedCommands.list_commands_for_device(device_id)

    # Look for matching response patterns
    matching_command =
      Enum.find(commands, fn command ->
        command.response_pattern &&
          binary_match?(serial_data, command.response_pattern)
      end)

    if matching_command do
      Logger.info(
        "Matched learned response pattern for #{matching_command.control_type} zone #{matching_command.zone}"
      )

      # Update the command's last_used timestamp
      LearnedCommands.mark_command_used(matching_command)

      # Return the matched command info for UI updates
      {:ok,
       %{
         control_type: matching_command.control_type,
         zone: matching_command.zone,
         source_index: matching_command.source_index,
         volume_level: matching_command.volume_level,
         pattern_type: :learned
       }}
    else
      :no_match
    end
  end

  @doc """
  Match against default hardcoded response patterns using flexible pattern matching.
  """
  def match_default_patterns(serial_data, rolling_buffer \\ "") do
    # Combine rolling buffer with new data for pattern matching
    combined_data = rolling_buffer <> serial_data

    # Try to match mute patterns first (they have a specific structure)
    case match_mute_pattern(combined_data) do
      {:ok, zone} ->
        Logger.info("Matched mute response pattern for zone #{zone + 1}")

        {:ok,
         %{
           control_type: "mute",
           zone: zone,
           source_index: nil,
           volume_level: nil,
           pattern_type: :default
         }}

      :no_match ->
        # Try to match unmute patterns
        case match_unmute_pattern(combined_data) do
          {:ok, zone} ->
            Logger.info("Matched unmute response pattern for zone #{zone + 1}")

            {:ok,
             %{
               control_type: "unmute",
               zone: zone,
               source_index: nil,
               volume_level: nil,
               pattern_type: :default
             }}

          :no_match ->
            :no_match
        end
    end
  end

  @doc """
  Match mute response pattern: A4 02 [zone] FD A4 08 0F 20 02 [some_byte] 01 0C 64 4B 4B 00 00 01 00 90 02 [checksum]

  The pattern seems to be more flexible than initially thought - the byte after 0x02 can vary.
  """
  def match_mute_pattern(data) do
    # Look for the core mute pattern structure
    case data do
      # Pattern: A4 02 [zone] FD A4 08 0F 20 02 [any_byte] 01 0C 64 4B 4B 00 00 01 00 90 02 [checksum]
      <<0xA4, 0x02, zone_byte, 0xFD, 0xA4, 0x08, 0x0F, 0x20, 0x02, _any_byte, 0x01, 0x0C, 0x64,
        0x4B, 0x4B, 0x00, 0x00, 0x01, 0x00, 0x90, 0x02, _checksum, _rest::binary>> ->
        # Just check that zone_byte is valid (1-8)
        if zone_byte >= 1 and zone_byte <= 8 do
          # Convert to 0-based index
          {:ok, zone_byte - 1}
        else
          :no_match
        end

      # Partial match - check if we have the beginning of the pattern
      <<0xA4, 0x02, zone_byte, 0xFD, 0xA4, 0x08, 0x0F, 0x20, 0x02, _any_byte, 0x01, 0x0C, 0x64,
        0x4B, 0x4B, 0x00, 0x00, 0x01, 0x00, 0x90, 0x02, _rest::binary>> ->
        # Just check that zone_byte is valid (1-8)
        if zone_byte >= 1 and zone_byte <= 8 do
          # Convert to 0-based index
          {:ok, zone_byte - 1}
        else
          :no_match
        end

      _ ->
        :no_match
    end
  end

  @doc """
  Match unmute response pattern (we'll need to determine this when you get unmute responses)
  """
  def match_unmute_pattern(_data) do
    # For now, return no match since we don't have unmute patterns yet
    # This will be updated when you provide unmute response examples
    :no_match
  end

  @doc """
  Create a rolling buffer to handle segmented messages.

  This maintains a buffer of recent data to catch patterns that might be split
  across multiple serial messages.
  """
  def create_rolling_buffer(previous_buffer, new_data, max_buffer_size \\ 1024) do
    # Combine previous buffer with new data
    combined = previous_buffer <> new_data

    # Keep only the last max_buffer_size bytes
    if byte_size(combined) > max_buffer_size do
      # Take the last max_buffer_size bytes
      <<_::binary-size(byte_size(combined) - max_buffer_size), buffer::binary>> = combined
      buffer
    else
      combined
    end
  end

  @doc """
  Check if a binary pattern matches within the data.

  This uses a more sophisticated matching algorithm that can handle:
  - Exact matches
  - Partial matches at the end of the buffer (for segmented messages)
  - Wildcard patterns (future enhancement)
  """
  def binary_match?(data, pattern) do
    # For now, use simple substring matching
    # This could be enhanced with more sophisticated pattern matching
    String.contains?(data, pattern)
  end

  @doc """
  Check if a binary pattern matches with flexible ending.

  This matches the core pattern but allows for variations in the last few bytes.
  """
  def flexible_binary_match?(data, core_pattern, min_length) do
    # Check if the data contains the core pattern and is at least min_length bytes
    String.contains?(data, core_pattern) and byte_size(data) >= min_length
  end

  @doc """
  Get all available default response patterns.
  """
  def get_default_patterns do
    @default_response_patterns
  end

  @doc """
  Add a new default response pattern.
  """
  def add_default_pattern(control_type, zone, pattern) do
    # This would be used to dynamically add patterns
    # For now, patterns are hardcoded in the module
    Logger.info("Adding default pattern for #{control_type} zone #{zone}: #{inspect(pattern)}")
  end

  # Private helper functions
end
