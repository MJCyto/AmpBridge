defmodule AmpBridge.SerialManager do
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

    device_paths =
      usb_devices
      |> Enum.map(& &1.path)
      |> Enum.filter(&(&1 != nil))

    assigned_device = AmpBridge.USBDeviceScanner.get_amp_device_assignment(1)

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
  Attempt to auto-connect adapters if they have been assigned.
  This can be called manually to retry auto-connection.
  """
  def attempt_auto_connection do
    GenServer.call(__MODULE__, :attempt_auto_connection)
  end

  @doc """
  Send command through an adapter
  """
  def send_command(adapter, data) when adapter in [@adapter_1, @adapter_2] do
    send_command(adapter, data, log_command: true)
  end

  @doc """
  Send command through an adapter with logging control
  """
  def send_command(adapter, data, opts \\ []) when adapter in [@adapter_1, @adapter_2] do
    log_command = Keyword.get(opts, :log_command, true)
    GenServer.call(__MODULE__, {:send_command, adapter, data, log_command})
  end

  @doc """
  Send hex command string through an adapter (parses hex string)
  """
  def send_hex_command(adapter, hex_string) when adapter in [@adapter_1, @adapter_2] do
    send_hex_command(adapter, hex_string, log_command: true)
  end

  @doc """
  Send hex command string through an adapter with logging control
  """
  def send_hex_command(adapter, hex_string, opts \\ [])
      when adapter in [@adapter_1, @adapter_2] do
    case parse_hex_command(hex_string) do
      {:ok, binary_data} ->
        case send_command(adapter, binary_data, opts) do
          :ok -> {:ok, binary_data}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Send raw binary data through an adapter (for relay functionality)
  """
  def send_raw_data(adapter, binary_data) when adapter in [@adapter_1, @adapter_2] do
    send_command(adapter, binary_data, log_command: false)
  end

  @doc """
  Get current connection status for both adapters
  """
  def get_connection_status do
    GenServer.call(__MODULE__, :get_connection_status, 2000)
  end

  @doc """
  Check CTS status for an adapter
  """
  def check_cts_status(adapter) when adapter in [@adapter_1, @adapter_2] do
    GenServer.call(__MODULE__, {:check_cts_status, adapter})
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
    {adapter_1_device, adapter_1_settings, adapter_2_device, adapter_2_settings} =
      load_adapter_assignments()

    initial_state = %__MODULE__{
      adapter_1_connection: nil,
      adapter_2_connection: nil,
      adapter_1_settings: adapter_1_settings,
      adapter_2_settings: adapter_2_settings,
      adapter_1_buffer: <<>>,
      adapter_2_buffer: <<>>,
      adapter_1_uart_pid: nil,
      adapter_2_uart_pid: nil
    }

    final_state = attempt_auto_connection(adapter_1_device, adapter_2_device, initial_state)

    Process.send_after(self(), :check_and_start_relay, 2000)

    {:ok, final_state}
  end

  @impl true
  def handle_call({:set_adapter_settings, adapter, settings}, _from, state) do
    new_state =
      case adapter do
        @adapter_1 -> %{state | adapter_1_settings: settings}
        @adapter_2 -> %{state | adapter_2_settings: settings}
      end

    case adapter do
      @adapter_1 ->
        if state.adapter_1_connection do
          save_adapter_assignment(:adapter_1, state.adapter_1_connection, settings)
        end

      @adapter_2 ->
        if state.adapter_2_connection do
          save_adapter_assignment(:adapter_2, state.adapter_2_connection, settings)
        end
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

              save_adapter_assignment(:adapter_1, device_path, state.adapter_1_settings)

              Logger.info("Adapter 1 connected to #{device_path}")

              maybe_auto_start_relay(new_state)

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

              save_adapter_assignment(:adapter_2, device_path, state.adapter_2_settings)

              Logger.info("Adapter 2 connected to #{device_path}")

              maybe_auto_start_relay(new_state)

              {:reply, {:ok, uart_pid}, new_state}

            {:error, reason} ->
              Logger.error("Failed to connect Adapter 2: #{reason}")
              {:reply, {:error, reason}, state}
          end
        end
    end
  end

  @impl true
  def handle_call(:attempt_auto_connection, _from, state) do
    {adapter_1_device, adapter_1_settings, adapter_2_device, adapter_2_settings} =
      load_adapter_assignments()

    new_state = %{
      state
      | adapter_1_settings: adapter_1_settings,
        adapter_2_settings: adapter_2_settings
    }

    final_state = attempt_auto_connection(adapter_1_device, adapter_2_device, new_state)

    {:reply, :ok, final_state}
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

        clear_adapter_assignment(:adapter_1)

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

        clear_adapter_assignment(:adapter_2)

        Logger.info("Adapter 2 disconnected")
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:send_command, adapter, data, log_command}, _from, state) do
    uart_pid =
      case adapter do
        @adapter_1 -> state.adapter_1_uart_pid
        @adapter_2 -> state.adapter_2_uart_pid
      end

    if uart_pid do
      case Circuits.UART.write(uart_pid, data) do
        :ok ->
          Logger.info("Command sent via #{adapter}: #{format_hex(data)}")

          if log_command do
            command_message = %{
              timestamp: DateTime.utc_now(),
              hex: format_hex(data),
              size: byte_size(data),
              decoded: %{
                type: "command",
                description: "Serial command sent",
                command: "serial_command"
              },
              adapter: :system,
              adapter_name: "System",
              adapter_color: "grey"
            }

            Phoenix.PubSub.broadcast(
              AmpBridge.PubSub,
              "serial_data",
              {:serial_data, data, command_message.decoded,
               %{
                 adapter: :system,
                 adapter_name: "System",
                 adapter_color: "grey"
               }}
            )
          end

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
  def handle_call({:check_cts_status, adapter}, _from, state) do
    uart_pid =
      case adapter do
        @adapter_1 -> state.adapter_1_uart_pid
        @adapter_2 -> state.adapter_2_uart_pid
      end

    if uart_pid do
      case Circuits.UART.read(uart_pid, 0) do
        {:ok, _data} ->
          # CTS is high (ready to receive)
          {:reply, {:ok, true}, state}
        {:error, :eagain} ->
          # CTS is low (not ready)
          {:reply, {:ok, false}, state}
        {:error, reason} ->
          Logger.error("Failed to check CTS status for #{adapter}: #{reason}")
          {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, "#{adapter} not connected"}, state}
    end
  end

  @impl true
  def handle_info(:check_and_start_relay, state) do
    if state.adapter_1_connection && state.adapter_2_connection do
      Logger.info("Both adapters already connected - checking if relay needs to be started")
      maybe_auto_start_relay(state)
    else
      Logger.debug("Not all adapters connected yet - skipping relay start check")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:circuits_uart, device_path, data}, state) do
    Logger.debug("Raw UART data received: #{inspect(data)}")
    Logger.debug("Data size: #{byte_size(data)} bytes")
    Logger.debug("Device path: #{inspect(device_path)}")
    Logger.debug("Adapter 1 device: #{inspect(state.adapter_1_connection)}")
    Logger.debug("Adapter 2 device: #{inspect(state.adapter_2_connection)}")

    adapter =
      cond do
        device_path == state.adapter_1_connection -> @adapter_1
        device_path == state.adapter_2_connection -> @adapter_2
        true -> nil
      end

    Logger.debug("Data from adapter: #{inspect(adapter)}")

    if adapter do
      process_serial_data(adapter, data, state)
    else
      Logger.warning("Received data from unknown device: #{inspect(device_path)}")
      {:noreply, state}
    end
  end

  # Private functions

  defp connect_to_device(device_path, settings) do
    Logger.info("Connecting to device: #{device_path} with settings: #{inspect(settings)}")

    if not File.exists?(device_path) do
      Logger.error("Device does not exist: #{device_path}")
      {:error, "Device does not exist: #{device_path}"}
    else
      baud_rate = Map.get(settings, :baud_rate, 57600)
      data_bits = Map.get(settings, :data_bits, 8)
      stop_bits = Map.get(settings, :stop_bits, 1)
      parity = Map.get(settings, :parity, :none)
      flow_control = Map.get(settings, :flow_control, true)

      Logger.debug(
        "UART settings: baud=#{baud_rate}, data_bits=#{data_bits}, stop_bits=#{stop_bits}, parity=#{parity}, flow_control=#{flow_control}"
      )

      case Circuits.UART.start_link() do
        {:ok, uart_pid} ->
          Logger.info("Started UART GenServer: #{inspect(uart_pid)}")

          uart_options = [
            speed: baud_rate,
            data_bits: data_bits,
            stop_bits: stop_bits,
            parity: parity
          ]

          uart_options =
            if flow_control do
              uart_options ++ [flow_control: :rts_cts]
            else
              uart_options
            end

          Logger.debug("UART options: #{inspect(uart_options)}")

          case Circuits.UART.open(uart_pid, device_path, uart_options) do
            :ok ->
              flow_status =
                if flow_control, do: " with RTS/CTS flow control", else: " without flow control"

              Logger.info(
                "Successfully opened serial port: #{device_path} at #{baud_rate} baud#{flow_status}"
              )

              Circuits.UART.configure(uart_pid, active: true)
              Logger.debug("UART configured with active: true for PID: #{inspect(uart_pid)}")
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
    Logger.debug("Processing serial data for #{adapter}: #{inspect(data)}")

    new_buffer =
      case adapter do
        @adapter_1 -> state.adapter_1_buffer <> data
        @adapter_2 -> state.adapter_2_buffer <> data
      end

    new_state =
      case adapter do
        @adapter_1 -> %{state | adapter_1_buffer: new_buffer}
        @adapter_2 -> %{state | adapter_2_buffer: new_buffer}
      end

    decoded = AmpBridge.SerialDecoder.decode_command(data)

    adapter_info = %{
      adapter: adapter,
      adapter_name: get_adapter_name(adapter),
      adapter_color: get_adapter_color(adapter)
    }

    Logger.debug("Broadcasting data: #{inspect(data)} from #{adapter}")

    Phoenix.PubSub.broadcast(AmpBridge.PubSub, "serial_data", {
      :serial_data,
      data,
      decoded,
      adapter_info
    })

    process_command_learning_data(adapter, data)

    {:noreply, new_state}
  end

  # Private helper functions

  defp attempt_auto_connection(adapter_1_device, adapter_2_device, state) do
    if adapter_1_device && adapter_2_device do
      Logger.info("Both adapters have been assigned - attempting auto-connection...")

      Logger.info("Auto-connecting adapter 1 to #{adapter_1_device}")

      state =
        case connect_to_device(adapter_1_device, state.adapter_1_settings) do
          {:ok, uart_pid} ->
            Logger.info("Successfully auto-connected adapter 1 to #{adapter_1_device}")
            %{state | adapter_1_connection: adapter_1_device, adapter_1_uart_pid: uart_pid}

          {:error, reason} ->
            Logger.warning("Failed to auto-connect adapter 1 to #{adapter_1_device}: #{reason}")
            state
        end

      Logger.info("Auto-connecting adapter 2 to #{adapter_2_device}")

      state =
        case connect_to_device(adapter_2_device, state.adapter_2_settings) do
          {:ok, uart_pid} ->
            Logger.info("Successfully auto-connected adapter 2 to #{adapter_2_device}")
            %{state | adapter_2_connection: adapter_2_device, adapter_2_uart_pid: uart_pid}

          {:error, reason} ->
            Logger.warning("Failed to auto-connect adapter 2 to #{adapter_2_device}: #{reason}")
            state
        end

      connection_count =
        [state.adapter_1_connection, state.adapter_2_connection]
        |> Enum.count(&(&1 != nil))

      Logger.info("Auto-connection complete: #{connection_count}/2 adapters connected")

      if connection_count == 2 do
        Logger.info("Both adapters connected during auto-connection - relay will start when needed")
      end

      state
    else
      Logger.debug(
        "Skipping auto-connection - adapters not fully assigned (adapter_1: #{inspect(adapter_1_device)}, adapter_2: #{inspect(adapter_2_device)})"
      )

      state
    end
  end

  defp maybe_auto_start_relay(state) do
    if state.adapter_1_connection && state.adapter_2_connection do
      Logger.info("Both adapters connected - auto-starting SerialRelay")
      case AmpBridge.SerialRelay.start_relay_with_status(true, true) do
        :ok ->
          Logger.info("SerialRelay auto-started successfully")
        {:error, reason} ->
          Logger.warning("Failed to auto-start SerialRelay: #{reason}")
      end
    end
  end

  defp load_adapter_assignments do
    default_settings = %{
      baud_rate: 57600,
      data_bits: 8,
      stop_bits: 1,
      parity: :none,
      flow_control: true
    }

    case AmpBridge.Devices.get_device(1) do
      nil ->
        {nil, default_settings, nil, default_settings}

      device ->
        adapter_1_device = device.adapter_1_device
        adapter_1_settings = device.adapter_1_settings || default_settings
        adapter_2_device = device.adapter_2_device
        adapter_2_settings = device.adapter_2_settings || default_settings

        {adapter_1_device, adapter_1_settings, adapter_2_device, adapter_2_settings}
    end
  end

  defp save_adapter_assignment(adapter, device_path, settings) do
    case AmpBridge.Devices.get_device(1) do
      nil ->
        AmpBridge.Devices.create_device(%{
          name: "Main Amplifier",
          adapter_1_device: if(adapter == :adapter_1, do: device_path, else: nil),
          adapter_1_settings: if(adapter == :adapter_1, do: settings, else: %{}),
          adapter_2_device: if(adapter == :adapter_2, do: device_path, else: nil),
          adapter_2_settings: if(adapter == :adapter_2, do: settings, else: %{})
        })

      device ->
        attrs =
          case adapter do
            :adapter_1 -> %{adapter_1_device: device_path, adapter_1_settings: settings}
            :adapter_2 -> %{adapter_2_device: device_path, adapter_2_settings: settings}
          end

        AmpBridge.Devices.update_device(device, attrs)
    end
  end

  defp clear_adapter_assignment(adapter) do
    case AmpBridge.Devices.get_device(1) do
      nil ->
        :ok

      device ->
        attrs =
          case adapter do
            :adapter_1 -> %{adapter_1_device: nil, adapter_1_settings: %{}}
            :adapter_2 -> %{adapter_2_device: nil, adapter_2_settings: %{}}
          end

        AmpBridge.Devices.update_device(device, attrs)
    end
  end

  defp process_command_learning_data(adapter, data) do
    device_id = 1

    try do
      AmpBridge.CommandLearner.process_learning_data(device_id, data, adapter)
    rescue
      error ->
        Logger.debug("No active learning session for device #{device_id}: #{inspect(error)}")
    end
  end
end
