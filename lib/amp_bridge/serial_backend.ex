defmodule AmpBridge.SerialBackend do
  @moduledoc """
  Backend module for managing multiple serial connections and data processing.
  Handles 2 separate USB adapters with independent connection settings.
  """

  use GenServer
  require Logger

  # Adapter identifiers
  @adapter_1 :adapter_1
  @adapter_2 :adapter_2

  defstruct [
    :adapter_1_connection,
    :adapter_2_connection,
    :adapter_1_settings,
    :adapter_2_settings,
    :adapter_1_buffer,
    :adapter_2_buffer,
    :adapter_1_uart_pid,
    :adapter_2_uart_pid
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get list of available serial devices
  """
  def get_available_devices do
    usb_devices = AmpBridge.USBDeviceScanner.get_devices()

    # Extract device paths from USB devices
    device_paths =
      usb_devices
      |> Enum.map(& &1.path)
      |> Enum.filter(&(&1 != nil))

    # Get assigned device to ensure it's always included
    assigned_device = AmpBridge.USBDeviceScanner.get_amp_device_assignment(1)

    # Always include assigned device if it exists
    all_devices =
      if assigned_device && !Enum.member?(device_paths, assigned_device) do
        [assigned_device | device_paths]
      else
        device_paths
      end

    Logger.info("Available serial devices: #{inspect(all_devices)}")
    all_devices
  end

  @doc """
  Set connection settings for an adapter
  """
  def set_adapter_settings(adapter, settings) when adapter in [@adapter_1, @adapter_2] do
    GenServer.call(__MODULE__, {:set_adapter_settings, adapter, settings})
  end

  @doc """
  Connect an adapter to a serial device
  """
  def connect_adapter(adapter, device_path) when adapter in [@adapter_1, @adapter_2] do
    GenServer.call(__MODULE__, {:connect_adapter, adapter, device_path})
  end

  @doc """
  Disconnect an adapter
  """
  def disconnect_adapter(adapter) when adapter in [@adapter_1, @adapter_2] do
    GenServer.call(__MODULE__, {:disconnect_adapter, adapter})
  end

  @doc """
  Send command through an adapter
  """
  def send_command(adapter, data) when adapter in [@adapter_1, @adapter_2] do
    GenServer.call(__MODULE__, {:send_command, adapter, data})
  end

  @doc """
  Send hex command string through an adapter (parses hex string)
  """
  def send_hex_command(adapter, hex_string) when adapter in [@adapter_1, @adapter_2] do
    case parse_hex_command(hex_string) do
      {:ok, binary_data} ->
        case send_command(adapter, binary_data) do
          :ok -> {:ok, binary_data}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get current connection status for both adapters
  """
  def get_connection_status do
    GenServer.call(__MODULE__, :get_connection_status)
  end

  @doc """
  Get adapter color for UI display
  """
  def get_adapter_color(@adapter_1), do: "blue"
  def get_adapter_color(@adapter_2), do: "green"

  @doc """
  Get adapter display name
  """
  def get_adapter_name(@adapter_1), do: "Adapter 1"
  def get_adapter_name(@adapter_2), do: "Adapter 2"

  @doc """
  Parse hex command string into binary data
  """
  def parse_hex_command(command_string) do
    # Remove spaces and convert to binary
    clean_command = command_string |> String.replace(" ", "") |> String.upcase()

    # Validate hex string (even number of characters)
    if rem(String.length(clean_command), 2) != 0 do
      {:error, "Hex command must have even number of characters"}
    else
      try do
        binary_data = Base.decode16!(clean_command, case: :upper)
        {:ok, binary_data}
      rescue
        ArgumentError -> {:error, "Invalid hex characters in command"}
      end
    end
  end

  @doc """
  Format binary data as hex string
  """
  def format_hex(binary_data) do
    binary_data
    |> :binary.bin_to_list()
    |> Enum.map(&String.pad_leading(Integer.to_string(&1, 16), 2, "0"))
    |> Enum.join(" ")
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok,
     %__MODULE__{
       adapter_1_connection: nil,
       adapter_2_connection: nil,
       adapter_1_settings: %{},
       adapter_2_settings: %{},
       adapter_1_buffer: <<>>,
       adapter_2_buffer: <<>>,
       adapter_1_uart_pid: nil,
       adapter_2_uart_pid: nil
     }}
  end

  @impl true
  def handle_call({:set_adapter_settings, adapter, settings}, _from, state) do
    new_state =
      case adapter do
        @adapter_1 -> %{state | adapter_1_settings: settings}
        @adapter_2 -> %{state | adapter_2_settings: settings}
      end

    Logger.info("Set #{adapter} settings: #{inspect(settings)}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:connect_adapter, adapter, device_path}, _from, state) do
    case adapter do
      @adapter_1 ->
        if state.adapter_1_connection do
          {:reply, {:error, "Adapter 1 already connected"}, state}
        else
          case connect_to_device(device_path, state.adapter_1_settings) do
            {:ok, uart_pid} ->
              new_state = %{
                state
                | adapter_1_connection: device_path,
                  adapter_1_uart_pid: uart_pid
              }

              Logger.info("Adapter 1 connected to #{device_path}")
              {:reply, {:ok, uart_pid}, new_state}

            {:error, reason} ->
              Logger.error("Failed to connect Adapter 1: #{reason}")
              {:reply, {:error, reason}, state}
          end
        end

      @adapter_2 ->
        if state.adapter_2_connection do
          {:reply, {:error, "Adapter 2 already connected"}, state}
        else
          case connect_to_device(device_path, state.adapter_2_settings) do
            {:ok, uart_pid} ->
              new_state = %{
                state
                | adapter_2_connection: device_path,
                  adapter_2_uart_pid: uart_pid
              }

              Logger.info("Adapter 2 connected to #{device_path}")
              {:reply, {:ok, uart_pid}, new_state}

            {:error, reason} ->
              Logger.error("Failed to connect Adapter 2: #{reason}")
              {:reply, {:error, reason}, state}
          end
        end
    end
  end

  @impl true
  def handle_call({:disconnect_adapter, adapter}, _from, state) do
    case adapter do
      @adapter_1 ->
        if state.adapter_1_uart_pid do
          Circuits.UART.close(state.adapter_1_uart_pid)
          Circuits.UART.stop(state.adapter_1_uart_pid)
        end

        new_state = %{
          state
          | adapter_1_connection: nil,
            adapter_1_uart_pid: nil,
            adapter_1_buffer: <<>>
        }

        Logger.info("Adapter 1 disconnected")
        {:reply, :ok, new_state}

      @adapter_2 ->
        if state.adapter_2_uart_pid do
          Circuits.UART.close(state.adapter_2_uart_pid)
          Circuits.UART.stop(state.adapter_2_uart_pid)
        end

        new_state = %{
          state
          | adapter_2_connection: nil,
            adapter_2_uart_pid: nil,
            adapter_2_buffer: <<>>
        }

        Logger.info("Adapter 2 disconnected")
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:send_command, adapter, data}, _from, state) do
    uart_pid =
      case adapter do
        @adapter_1 -> state.adapter_1_uart_pid
        @adapter_2 -> state.adapter_2_uart_pid
      end

    if uart_pid do
      case Circuits.UART.write(uart_pid, data) do
        :ok ->
          Logger.info("Command sent via #{adapter}: #{format_hex(data)}")
          {:reply, :ok, state}

        {:error, reason} ->
          Logger.error("Failed to send command via #{adapter}: #{reason}")
          {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, "#{adapter} not connected"}, state}
    end
  end

  @impl true
  def handle_call(:get_connection_status, _from, state) do
    status = %{
      adapter_1: %{
        connected: state.adapter_1_connection != nil,
        device: state.adapter_1_connection,
        settings: state.adapter_1_settings
      },
      adapter_2: %{
        connected: state.adapter_2_connection != nil,
        device: state.adapter_2_connection,
        settings: state.adapter_2_settings
      }
    }

    {:reply, status, state}
  end

  @impl true
  def handle_info({:circuits_uart, uart_pid, data}, state) do
    # Determine which adapter this data came from
    adapter =
      cond do
        uart_pid == state.adapter_1_uart_pid -> @adapter_1
        uart_pid == state.adapter_2_uart_pid -> @adapter_2
        true -> nil
      end

    if adapter do
      # Process the data and broadcast with adapter info
      process_serial_data(adapter, data, state)
    else
      {:noreply, state}
    end
  end

  # Private functions

  defp connect_to_device(device_path, settings) do
    Logger.info("Connecting to device: #{device_path} with settings: #{inspect(settings)}")

    # Check if device exists
    if not File.exists?(device_path) do
      Logger.error("Device does not exist: #{device_path}")
      {:error, "Device does not exist: #{device_path}"}
    else
      # Extract settings with defaults
      baud_rate = Map.get(settings, :baud_rate, 9600)
      data_bits = Map.get(settings, :data_bits, 8)
      stop_bits = Map.get(settings, :stop_bits, 1)
      parity = Map.get(settings, :parity, :none)

      # Start a UART GenServer
      case Circuits.UART.start_link() do
        {:ok, uart_pid} ->
          Logger.info("Started UART GenServer: #{inspect(uart_pid)}")

          # Open the device with custom settings
          case Circuits.UART.open(uart_pid, device_path,
                 speed: baud_rate,
                 data_bits: data_bits,
                 stop_bits: stop_bits,
                 parity: parity
               ) do
            :ok ->
              Logger.info("Successfully opened serial port: #{device_path} at #{baud_rate} baud")
              # Set up message handling for incoming data
              Circuits.UART.configure(uart_pid, active: true)
              {:ok, uart_pid}

            {:error, reason} ->
              Logger.error("Failed to open serial port #{device_path}: #{inspect(reason)}")
              Circuits.UART.stop(uart_pid)

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

  defp process_serial_data(adapter, data, state) do
    # Add data to appropriate buffer
    {new_buffer, frames} =
      case adapter do
        @adapter_1 ->
          new_buffer = state.adapter_1_buffer <> data
          {frames, remaining} = extract_frames(new_buffer)
          {remaining, frames}

        @adapter_2 ->
          new_buffer = state.adapter_2_buffer <> data
          {frames, remaining} = extract_frames(new_buffer)
          {remaining, frames}
      end

    # Update state with new buffer
    new_state =
      case adapter do
        @adapter_1 -> %{state | adapter_1_buffer: new_buffer}
        @adapter_2 -> %{state | adapter_2_buffer: new_buffer}
      end

    # Decode and broadcast each frame with adapter info
    for frame <- frames do
      decoded = AmpBridge.SerialDecoder.decode_command(frame)

      adapter_info = %{
        adapter: adapter,
        adapter_name: get_adapter_name(adapter),
        adapter_color: get_adapter_color(adapter)
      }

      Phoenix.PubSub.broadcast(AmpBridge.PubSub, "serial_data", {
        :serial_data,
        frame,
        decoded,
        adapter_info
      })
    end

    {:noreply, new_state}
  end

  defp extract_frames(buffer) do
    # Known ELAN frame headers
    headers = [<<0xA4, 0x02>>, <<0x41, 0x64, 0x4B, 0x4B>>]
    extract_frames(buffer, headers, [])
  end

  defp extract_frames(buffer, headers, frames) do
    case find_next_frame(buffer, headers) do
      {:ok, frame, remaining} ->
        extract_frames(remaining, headers, [frame | frames])

      :not_found ->
        {Enum.reverse(frames), buffer}
    end
  end

  defp find_next_frame(buffer, headers) do
    Enum.find_value(headers, fn header ->
      case :binary.match(buffer, header) do
        {start, _length} ->
          # Found header, look for next header or end of buffer
          next_start = find_next_header_start(buffer, start + byte_size(header), headers)
          frame = :binary.part(buffer, start, next_start - start)
          remaining = :binary.part(buffer, next_start, byte_size(buffer) - next_start)
          {:ok, frame, remaining}

        :nomatch ->
          nil
      end
    end) || :not_found
  end

  defp find_next_header_start(buffer, start_pos, headers) do
    # Search for headers starting from the given position
    search_buffer = :binary.part(buffer, start_pos, byte_size(buffer) - start_pos)

    case Enum.find_value(headers, fn header ->
           case :binary.match(search_buffer, header) do
             {pos, _length} -> start_pos + pos
             :nomatch -> nil
           end
         end) do
      nil -> byte_size(buffer)
      pos -> pos
    end
  end
end
