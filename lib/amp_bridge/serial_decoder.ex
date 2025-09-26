defmodule AmpBridge.SerialDecoder do
  @moduledoc """
  Serial communication and ELAN protocol decoder for real-time command detection.
  """

  use GenServer
  require Logger

  # Known ELAN frame headers - updated based on actual data patterns
  @headers [
    # Volume control command
    <<0xA4, 0x02>>,
    # AdKK header
    <<0x41, 0x64, 0x4B, 0x4B>>,
    # Command frame header
    <<0xA4, 0x05>>,
    # Command frame data
    <<0x06, 0xFF>>,
    # Status/response header
    <<0xA4, 0x08>>,
    # Settings protocol headers
    # Status query
    <<0xA4, 0x00>>,
    # Settings request
    <<0xA4, 0x01>>,
    # Data transfer
    <<0xA4, 0x06>>
  ]


  defstruct [
    :serial_port,
    :port_name,
    :is_capturing,
    :buffer
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_capture(device_path, settings \\ %{}) do
    GenServer.call(__MODULE__, {:start_capture, device_path, settings})
  end

  def stop_capture do
    GenServer.call(__MODULE__, :stop_capture)
  end

  def test_decode_command(data) do
    decode_command(data)
  end

  def send_command(data) do
    GenServer.call(__MODULE__, {:send_command, data})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok,
     %__MODULE__{
       serial_port: nil,
       port_name: nil,
       is_capturing: false,
       buffer: <<>>
     }}
  end

  @impl true
  def handle_call({:start_capture, device_path, settings}, _from, state) do
    if state.is_capturing do
      Logger.warning("Already capturing from #{state.port_name}. Stop current capture first.")

      {:reply, {:error, "Already capturing from #{state.port_name}. Stop current capture first."},
       state}
    else
      case open_serial_port(device_path, settings) do
        {:ok, port} ->
          Logger.info(
            "Started serial capture from #{device_path} with settings: #{inspect(settings)}"
          )

          {:reply, {:ok, port},
           %{state | serial_port: port, port_name: device_path, is_capturing: true}}

        {:error, reason} ->
          Logger.error("Failed to open serial port #{device_path}: #{reason}")
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call(:stop_capture, _from, state) do
    if state.serial_port do
      Circuits.UART.close(state.serial_port)
      Circuits.UART.stop(state.serial_port)
    end

    Logger.info("Stopped serial capture")
    {:reply, :ok, %{state | serial_port: nil, port_name: nil, is_capturing: false, buffer: <<>>}}
  end

  @impl true
  def handle_call({:send_command, data}, _from, state) do
    Logger.info(
      "Send command request: is_capturing=#{state.is_capturing}, port=#{inspect(state.serial_port)}"
    )

    if state.is_capturing and state.serial_port do
      Logger.info("Sending command: #{format_hex(data)}")

      case Circuits.UART.write(state.serial_port, data) do
        :ok ->
          Logger.info("Command sent successfully via UART")
          {:reply, :ok, state}

        {:error, reason} ->
          Logger.error("Failed to send command via UART: #{reason}")
          {:reply, {:error, reason}, state}
      end
    else
      error_msg =
        if not state.is_capturing,
          do: "Serial capture not active",
          else: "Serial port not available"

      Logger.error("Cannot send command: #{error_msg}")
      {:reply, {:error, error_msg}, state}
    end
  end

  @impl true
  def handle_info({:circuits_uart, _message_id, data}, state) do
    if state.is_capturing do
      # Add data to buffer
      new_buffer = state.buffer <> data

      # Process complete frames
      {frames, remaining_buffer} = extract_frames(new_buffer)

      # Decode and broadcast each frame
      for frame <- frames do
        Phoenix.PubSub.broadcast(AmpBridge.PubSub, "serial_data", {:serial_data, frame})
      end

      {:noreply, %{state | buffer: remaining_buffer}}
    else
      {:noreply, state}
    end
  end

  # Private functions

  defp open_serial_port(device_path, settings) do
    Logger.info(
      "Attempting to open serial port: #{device_path} with settings: #{inspect(settings)}"
    )

    # Extract settings with defaults
    baud_rate = Map.get(settings, :baud_rate, 9600)
    data_bits = Map.get(settings, :data_bits, 8)
    stop_bits = Map.get(settings, :stop_bits, 1)
    parity = Map.get(settings, :parity, :none)

    Logger.info(
      "Extracted settings: baud_rate=#{baud_rate}, data_bits=#{data_bits}, stop_bits=#{stop_bits}, parity=#{parity}"
    )

    # Check if device exists
    if not File.exists?(device_path) do
      Logger.error("Device does not exist: #{device_path}")
      {:error, "Device does not exist: #{device_path}"}
    else
      # Check device permissions
      case File.stat(device_path) do
        {:ok, stat} ->
          Logger.info("Device permissions: #{stat.mode}")

        {:error, _} ->
          Logger.warning("Could not check device permissions")
      end

      # Start a UART GenServer
      case Circuits.UART.start_link() do
        {:ok, uart_pid} ->
          Logger.info("Started UART GenServer: #{inspect(uart_pid)}")

          # Open the device with custom settings
          open_result =
            Circuits.UART.open(uart_pid, device_path,
              speed: baud_rate,
              data_bits: data_bits,
              stop_bits: stop_bits,
              parity: parity
            )

          Logger.info("UART.open result: #{inspect(open_result)}")

          case open_result do
            :ok ->
              Logger.info("Successfully opened serial port: #{device_path} at #{baud_rate} baud")
              # Set up message handling for incoming data
              Circuits.UART.configure(uart_pid, active: true)
              {:ok, uart_pid}

            {:error, reason} ->
              Logger.error("Failed to open serial port #{device_path}: #{inspect(reason)}")
              # Clean up the UART process
              Circuits.UART.stop(uart_pid)
              # Provide helpful error message for common permission issues
              error_msg =
                case reason do
                  :eacces -> "Permission denied - user may need to be in dialout group"
                  :eagain -> "Device busy - may be in use by another process"
                  _ -> "Error: #{inspect(reason)}"
                end

              {:error, error_msg}
          end

        {:error, reason} ->
          Logger.error("Failed to start UART GenServer: #{inspect(reason)}")
          {:error, "Failed to start UART GenServer: #{inspect(reason)}"}
      end
    end
  end

  defp extract_frames(buffer) do
    extract_frames(buffer, [])
  end

  defp extract_frames(buffer, frames) do
    case find_next_frame(buffer) do
      {:ok, frame, remaining} ->
        extract_frames(remaining, [frame | frames])

      :not_found ->
        {Enum.reverse(frames), buffer}
    end
  end

  defp find_next_frame(buffer) do
    Enum.find_value(@headers, fn header ->
      case :binary.match(buffer, header) do
        {start, _length} ->
          # Found header, look for next header or end of buffer
          next_start = find_next_header_start(buffer, start + byte_size(header))
          frame = :binary.part(buffer, start, next_start - start)
          remaining = :binary.part(buffer, next_start, byte_size(buffer) - next_start)
          {:ok, frame, remaining}

        :nomatch ->
          nil
      end
    end) || :not_found
  end

  defp find_next_header_start(buffer, start_pos) do
    # Search for headers starting from the given position
    search_buffer = :binary.part(buffer, start_pos, byte_size(buffer) - start_pos)

    case Enum.find_value(@headers, fn header ->
           case :binary.match(search_buffer, header) do
             {pos, _length} -> start_pos + pos
             :nomatch -> nil
           end
         end) do
      nil -> byte_size(buffer)
      pos -> pos
    end
  end

  def decode_command(raw_data) do
    hex_string =
      raw_data
      |> :binary.bin_to_list()
      |> Enum.map(&String.pad_leading(Integer.to_string(&1, 16), 2, "0"))
      |> Enum.join(" ")

    %{
      hex: hex_string,
      raw: raw_data
    }
  end




  defp format_hex(binary_data) do
    binary_data
    |> :binary.bin_to_list()
    |> Enum.map(&String.pad_leading(Integer.to_string(&1, 16), 2, "0"))
    |> Enum.join(" ")
  end
end
