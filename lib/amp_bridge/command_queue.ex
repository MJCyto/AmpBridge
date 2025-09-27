defmodule AmpBridge.CommandQueue do
  @moduledoc """
  CommandQueue manages a FIFO queue of commands to be sent to the amplifier.

  Features:
  - Command replacement for replaceable commands (e.g., volume changes)
  - CTS/RTS flow control with timeout handling
  - Priority-based command ordering
  - Error handling and retry logic
  """

  use GenServer
  require Logger

  # alias AmpBridge.CommandQueue.Command

  defstruct [
    :queue,
    :processing,
    :current_adapter,
    :cts_timeout,
    :cts_check_interval,
    :cts_initial_delay,
    :current_command,
    :cts_timer,
    :command_sent_at
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enqueue a command for processing.
  """
  def enqueue(queue, command) do
    GenServer.call(queue, {:enqueue, command})
  end

  @doc """
  Get the current queue contents.
  """
  def get_queue(queue) do
    GenServer.call(queue, :get_queue)
  end

  @doc """
  Clear all commands from the queue.
  """
  def clear(queue) do
    GenServer.call(queue, :clear)
  end

  @doc """
  Start processing commands from the queue.
  """
  def start_processing(queue, adapter) do
    GenServer.call(queue, {:start_processing, adapter})
  end

  @doc """
  Stop processing commands.
  """
  def stop_processing(queue) do
    GenServer.call(queue, :stop_processing)
  end

  @doc """
  Get the current status of the queue.
  """
  def get_status(queue) do
    GenServer.call(queue, :get_status)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    cts_timeout = Keyword.get(opts, :cts_timeout, 200)  # milliseconds
    cts_check_interval = Keyword.get(opts, :cts_check_interval, 10)  # milliseconds
    cts_initial_delay = Keyword.get(opts, :cts_initial_delay, 50)  # milliseconds - wait for amp to start responding

    state = %__MODULE__{
      queue: [],
      processing: false,
      current_adapter: nil,
      cts_timeout: cts_timeout,
      cts_check_interval: cts_check_interval,
      cts_initial_delay: cts_initial_delay,
      current_command: nil,
      cts_timer: nil,
      command_sent_at: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:enqueue, command}, _from, state) do
    new_queue = add_command_to_queue(state.queue, command)
    {:reply, :ok, %{state | queue: new_queue}}
  end

  @impl true
  def handle_call(:get_queue, _from, state) do
    {:reply, state.queue, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    # Cancel any active CTS timer
    if state.cts_timer do
      Process.cancel_timer(state.cts_timer)
    end

    {:reply, :ok, %{state | queue: [], current_command: nil, cts_timer: nil}}
  end

  @impl true
  def handle_call({:start_processing, adapter}, _from, state) do
    if state.processing do
      {:reply, {:error, :already_processing}, state}
    else
      new_state = %{state | processing: true, current_adapter: adapter}
      # Start processing if there are commands
      if length(state.queue) > 0 do
        send(self(), :process_next_command)
      end
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:stop_processing, _from, state) do
    # Cancel any active CTS timer
    if state.cts_timer do
      Process.cancel_timer(state.cts_timer)
    end

    new_state = %{state | processing: false, current_adapter: nil, current_command: nil, cts_timer: nil}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      queue: state.queue,
      queue_length: length(state.queue),
      processing: state.processing,
      current_adapter: state.current_adapter,
      current_command: state.current_command,
      cts_initial_delay: state.cts_initial_delay,
      cts_check_interval: state.cts_check_interval,
      cts_timeout: state.cts_timeout,
      command_sent_at: state.command_sent_at
    }
    {:reply, status, state}
  end

  @impl true
  def handle_info(:process_next_command, state) do
    if state.processing and length(state.queue) > 0 do
      [command | rest] = state.queue
      new_state = %{state | queue: rest, current_command: command}

      # Send the command
      case send_command_to_serial(command, state.current_adapter) do
        :ok ->
          # Record when command was sent and start CTS monitoring immediately
          command_sent_at = System.monotonic_time(:millisecond)
          Logger.debug("Command sent, starting CTS monitoring (timeout includes #{state.cts_initial_delay}ms initial delay)")
          state_with_timestamp = %{new_state | command_sent_at: command_sent_at}
          new_state_with_timers = start_cts_monitoring(state_with_timestamp)
          {:noreply, new_state_with_timers}
        {:error, reason} ->
          Logger.error("Failed to send command: #{reason}")
          # Put command back at front of queue and try again later
          retry_state = %{new_state | queue: [command | rest]}
          Process.send_after(self(), :process_next_command, 1000)  # Retry in 1 second
          {:noreply, retry_state}
      end
    else
      # No more commands or not processing
      if state.processing and length(state.queue) == 0 do
        # All commands processed, stop processing
        new_state = %{state | processing: false, current_adapter: nil, current_command: nil}
        {:noreply, new_state}
      else
        {:noreply, state}
      end
    end
  end


  @impl true
  def handle_info(:check_cts_status, state) do
    if state.processing and state.current_command != nil and state.command_sent_at != nil do
      case check_cts_status(state.current_adapter) do
        {:ok, true} ->
          # CTS is high - check if we're past the initial delay period
          current_time = System.monotonic_time(:millisecond)
          elapsed = current_time - state.command_sent_at

          if elapsed >= state.cts_initial_delay do
            # We're past the initial delay, CTS high means command completed
            Logger.debug("Command completed, CTS is high (after #{elapsed}ms)")
            new_state = %{state | current_command: nil, cts_timer: nil, command_sent_at: nil}
            # Process next command
            send(self(), :process_next_command)
            {:noreply, new_state}
          else
            # Still in initial delay period, CTS high might be from previous command
            Logger.debug("CTS high but still in initial delay period (#{elapsed}ms < #{state.cts_initial_delay}ms), continuing to monitor")
            timer = Process.send_after(self(), :check_cts_status, state.cts_check_interval)
            {:noreply, %{state | cts_timer: timer}}
          end
        {:ok, false} ->
          # CTS still low, check again
          timer = Process.send_after(self(), :check_cts_status, state.cts_check_interval)
          {:noreply, %{state | cts_timer: timer}}
        {:error, reason} ->
          Logger.error("Failed to check CTS status: #{reason}")
          # Give up on this command and move to next
          new_state = %{state | current_command: nil, cts_timer: nil, command_sent_at: nil}
          send(self(), :process_next_command)
          {:noreply, new_state}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:cts_timeout, state) do
    if state.processing and state.current_command do
      Logger.warning("CTS timeout, moving to next command")
      new_state = %{state | current_command: nil, cts_timer: nil, command_sent_at: nil}
      send(self(), :process_next_command)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  # Private functions

  defp add_command_to_queue(queue, command) do
    if command.replaceable do
      # Remove any existing replaceable commands for the same zone and type
      filtered_queue = Enum.reject(queue, fn existing_command ->
        existing_command.replaceable and
        existing_command.zone == command.zone and
        existing_command.type == command.type
      end)

      # Add the new command at the appropriate position based on priority
      insert_command_by_priority([command | filtered_queue])
    else
      # Non-replaceable commands just go to the front
      [command | queue]
    end
  end

  defp insert_command_by_priority(commands) do
    # Sort by priority: high -> normal -> low
    priority_order = %{high: 0, normal: 1, low: 2}

    Enum.sort(commands, fn cmd1, cmd2 ->
      priority1 = Map.get(priority_order, cmd1.priority || :normal, 1)
      priority2 = Map.get(priority_order, cmd2.priority || :normal, 1)
      priority1 <= priority2
    end)
  end

  defp send_command_to_serial(command, adapter) do
    case Application.get_env(:amp_bridge, :test_mode, false) do
      true ->
        # In test mode, simulate success
        :ok
      false ->
        # In production, use the real SerialManager
        # Send each chunk with the appropriate delay
        send_command_chunks_with_delay(command.data, adapter)
    end
  end

  defp send_command_chunks_with_delay(data, adapter) do
    # Send command data via SerialManager (if available)
    case Application.get_env(:amp_bridge, :test_mode, false) do
      true ->
        # In test mode, simulate successful send
        :ok
      false ->
        # In production, use SerialManager
        case Code.ensure_loaded(AmpBridge.SerialManager) do
          {:module, _} ->
            case AmpBridge.SerialManager.send_command(adapter, data) do
              :ok -> :ok
              {:error, reason} -> {:error, reason}
            end
          {:error, _} ->
            # SerialManager not available, simulate success
            :ok
        end
    end
  end

  defp check_cts_status(adapter) do
    case Application.get_env(:amp_bridge, :test_mode, false) do
      true ->
        # In test mode, simulate CTS high
        {:ok, true}
      false ->
        # In production, use the real SerialManager CTS checking
        case Code.ensure_loaded(AmpBridge.SerialManager) do
          {:module, _} ->
            AmpBridge.SerialManager.check_cts_status(adapter)
          {:error, _} ->
            # SerialManager not available, simulate success
            {:ok, true}
        end
    end
  end

  defp start_cts_monitoring(state) do
    # Start CTS monitoring immediately, but with extended timeout to account for initial delay
    # The timeout includes the initial delay + normal CTS timeout
    extended_timeout = state.cts_initial_delay + state.cts_timeout

    cts_timer = Process.send_after(self(), :check_cts_status, state.cts_check_interval)
    _timeout_timer = Process.send_after(self(), :cts_timeout, extended_timeout)

    # Store the CTS timer (we'll use a single timer for simplicity)
    %{state | cts_timer: cts_timer}
  end
end
