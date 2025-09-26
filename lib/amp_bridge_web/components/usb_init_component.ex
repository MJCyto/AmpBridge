defmodule AmpBridgeWeb.USBInitComponent do
  use AmpBridgeWeb, :live_component
  require Logger

  import AmpBridgeWeb.SerialAnalysis.AdapterCard

  @adapter_1 :adapter_1
  @adapter_2 :adapter_2

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    # Get available serial devices
    available_devices = AmpBridge.SerialManager.get_available_devices()

    # Get connection status
    connection_status = AmpBridge.SerialManager.get_connection_status()

    # Default settings for ELAN amplifiers
    default_settings = %{
      baud_rate: 57600,
      data_bits: 8,
      stop_bits: 1,
      parity: :none,
      flow_control: true
    }

    # Use default settings if adapter settings are empty
    adapter_1_settings =
      if connection_status.adapter_1.settings == %{} do
        default_settings
      else
        connection_status.adapter_1.settings
      end

    adapter_2_settings =
      if connection_status.adapter_2.settings == %{} do
        default_settings
      else
        connection_status.adapter_2.settings
      end

    socket =
      assign(socket,
        available_devices: available_devices,
        adapter_1_device: connection_status.adapter_1.device,
        adapter_1_settings: adapter_1_settings,
        adapter_1_original_settings: adapter_1_settings,
        adapter_1_connected: connection_status.adapter_1.connected,
        adapter_1_settings_changed: false,
        adapter_2_device: connection_status.adapter_2.device,
        adapter_2_settings: adapter_2_settings,
        adapter_2_original_settings: adapter_2_settings,
        adapter_2_connected: connection_status.adapter_2.connected,
        adapter_2_settings_changed: false,
        show_advanced_settings: false,
        amp_id: assigns.amp_id,
        # Auto-detection state (passed from parent)
        auto_detection_active: assigns.auto_detection_active,
        adapter_1_name: assigns.adapter_1_name,
        adapter_2_name: assigns.adapter_2_name,
        adapter_1_role: assigns.adapter_1_role,
        adapter_2_role: assigns.adapter_2_role,
        detection_status: assigns.detection_status
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("set_adapter_settings", %{"adapter" => adapter} = params, socket) do
    # Extract settings from the form parameters, excluding _target and adapter
    settings = Map.drop(params, ["_target", "adapter"])
    adapter_atom = String.to_atom(adapter)

    # Convert string values to appropriate types
    processed_settings = %{
      baud_rate: String.to_integer(settings["baud_rate"]),
      data_bits: String.to_integer(settings["data_bits"]),
      stop_bits: String.to_integer(settings["stop_bits"]),
      parity: String.to_atom(settings["parity"]),
      flow_control: settings["flow_control"] == "rts_cts"
    }

    case AmpBridge.SerialManager.set_adapter_settings(adapter_atom, processed_settings) do
      :ok ->
        # Update socket assigns and compute if settings changed
        socket =
          case adapter_atom do
            @adapter_1 ->
              original = socket.assigns.adapter_1_original_settings
              settings_changed = processed_settings != original

              assign(socket,
                adapter_1_settings: processed_settings,
                adapter_1_settings_changed: settings_changed
              )

            @adapter_2 ->
              original = socket.assigns.adapter_2_original_settings
              settings_changed = processed_settings != original

              assign(socket,
                adapter_2_settings: processed_settings,
                adapter_2_settings_changed: settings_changed
              )
          end

        {:noreply, put_flash(socket, :info, "#{adapter} settings updated")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update #{adapter} settings: #{reason}")}
    end
  end

  @impl true
  def handle_event("connect_adapter", %{"adapter" => adapter, "device" => device}, socket) do
    adapter_atom = String.to_atom(adapter)

    # Don't connect if no device selected
    if device == "" do
      {:noreply, socket}
    else
      case AmpBridge.SerialManager.connect_adapter(adapter_atom, device) do
        {:ok, _uart_pid} ->
          # Update socket assigns
          socket =
            case adapter_atom do
              @adapter_1 ->
                assign(socket,
                  adapter_1_device: device,
                  adapter_1_connected: true
                )

              @adapter_2 ->
                assign(socket,
                  adapter_2_device: device,
                  adapter_2_connected: true
                )
            end

          {:noreply, put_flash(socket, :info, "#{adapter} connected to #{device}")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to connect #{adapter}: #{reason}")}
      end
    end
  end

  @impl true
  def handle_event("reconnect_adapter", %{"adapter" => adapter, "device" => device}, socket) do
    adapter_atom = String.to_atom(adapter)

    # First disconnect, then reconnect
    case AmpBridge.SerialManager.disconnect_adapter(adapter_atom) do
      :ok ->
        # Small delay to ensure disconnection is complete
        Process.sleep(100)

        case AmpBridge.SerialManager.connect_adapter(adapter_atom, device) do
          {:ok, _uart_pid} ->
            # Update socket assigns
            socket =
              case adapter_atom do
                @adapter_1 ->
                  assign(socket,
                    adapter_1_device: device,
                    adapter_1_connected: true,
                    adapter_1_original_settings: socket.assigns.adapter_1_settings,
                    adapter_1_settings_changed: false
                  )

                @adapter_2 ->
                  assign(socket,
                    adapter_2_device: device,
                    adapter_2_connected: true,
                    adapter_2_original_settings: socket.assigns.adapter_2_settings,
                    adapter_2_settings_changed: false
                  )
              end

            {:noreply,
             put_flash(socket, :info, "#{adapter} reconnected to #{device} with new settings")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to reconnect #{adapter}: #{reason}")}
        end

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to disconnect #{adapter} for reconnection: #{reason}")}
    end
  end

  @impl true
  def handle_event("disconnect_adapter", %{"adapter" => adapter}, socket) do
    adapter_atom = String.to_atom(adapter)

    case AmpBridge.SerialManager.disconnect_adapter(adapter_atom) do
      :ok ->
        # Update socket assigns
        socket =
          case adapter_atom do
            @adapter_1 ->
              assign(socket,
                adapter_1_device: nil,
                adapter_1_connected: false
              )

            @adapter_2 ->
              assign(socket,
                adapter_2_device: nil,
                adapter_2_connected: false
              )
          end

        {:noreply, put_flash(socket, :info, "#{adapter} disconnected")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to disconnect #{adapter}: #{reason}")}
    end
  end

  @impl true
  def handle_event("refresh_devices", _params, socket) do
    available_devices = AmpBridge.SerialManager.get_available_devices()
    {:noreply, assign(socket, available_devices: available_devices)}
  end

  @impl true
  def handle_event("toggle_advanced_settings", _params, socket) do
    {:noreply, assign(socket, show_advanced_settings: !socket.assigns.show_advanced_settings)}
  end

  @impl true
  def handle_event("start_auto_detection", _params, socket) do
    if socket.assigns.adapter_1_connected && socket.assigns.adapter_2_connected do
      # Send event to parent LiveView
      send(self(), {:start_auto_detection, socket.assigns.amp_id})
      {:noreply, socket}
    else
      {:noreply,
       put_flash(socket, :error, "Both adapters must be connected to start auto-detection")}
    end
  end

  @impl true
  def handle_event("stop_auto_detection", _params, socket) do
    # Send event to parent LiveView
    send(self(), {:stop_auto_detection, socket.assigns.amp_id})
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_adapter_name", %{"adapter" => adapter, "value" => name}, socket) do
    # Send event to parent LiveView
    send(self(), {:update_adapter_name, adapter, name})
    {:noreply, socket}
  end


  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header -->
      <div class="flex justify-between items-center">
        <div>
          <h3 class="text-lg font-semibold text-neutral-100">USB Serial Adapters</h3>
          <p class="text-sm text-neutral-400">Connect and configure USB-to-serial adapters for your amplifier</p>
        </div>
        <div class="flex items-center space-x-3">
          <label class="flex items-center space-x-2 text-sm font-medium text-neutral-300 hover:text-neutral-100 transition-colors cursor-pointer">
            <input
              type="checkbox"
              phx-click="toggle_advanced_settings"
              phx-target={@myself}
              checked={@show_advanced_settings}
              class="w-4 h-4 text-teal-600 bg-neutral-500 border-neutral-400 rounded focus:ring-teal-500 focus:ring-2"
            />
            <span>Advanced Settings</span>
          </label>
          <button
            phx-click="refresh_devices"
            phx-target={@myself}
            class="px-3 py-1 bg-blue-600 text-white text-sm rounded hover:bg-blue-700"
          >
            Refresh Devices
          </button>
        </div>
      </div>

      <!-- Device Status Summary -->
      <div class="bg-neutral-600 rounded-lg p-4">
        <div class="flex justify-between items-center mb-3">
          <h4 class="text-sm font-medium text-neutral-100">Connection Status</h4>
          <div class="text-sm text-neutral-300">
            <%= if @adapter_1_connected && @adapter_2_connected do %>
              <span class="text-green-400">✓ Both adapters connected</span>
            <% else %>
              <span class="text-yellow-400">
                <%= if @adapter_1_connected or @adapter_2_connected do %>
                  <%= if @adapter_1_connected and not @adapter_2_connected, do: "1 of 2 connected" %>
                  <%= if @adapter_2_connected and not @adapter_1_connected, do: "1 of 2 connected" %>
                <% else %>
                  0 of 2 connected
                <% end %>
              </span>
            <% end %>
          </div>
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div class="flex items-center space-x-2">
            <div class={[
              "w-3 h-3 rounded-full",
              if(@adapter_1_connected, do: "bg-green-500", else: "bg-neutral-500")
            ]}></div>
            <span class="text-sm text-neutral-300">
              Adapter 1: <%= if @adapter_1_connected, do: "Connected to #{@adapter_1_device}", else: "Not connected" %>
            </span>
          </div>
          <div class="flex items-center space-x-2">
            <div class={[
              "w-3 h-3 rounded-full",
              if(@adapter_2_connected, do: "bg-green-500", else: "bg-neutral-500")
            ]}></div>
            <span class="text-sm text-neutral-300">
              Adapter 2: <%= if @adapter_2_connected, do: "Connected to #{@adapter_2_device}", else: "Not connected" %>
            </span>
          </div>
        </div>
      </div>

      <!-- Adapter Cards -->
      <div class="flex flex-row gap-6">
        <.adapter_card
          adapter_name="Adapter 1"
          adapter_color="blue"
          connected={@adapter_1_connected}
          device={@adapter_1_device}
          available_devices={@available_devices}
          settings={@adapter_1_settings}
          settings_changed={@adapter_1_settings_changed}
          adapter_key={:adapter_1}
          show_advanced={@show_advanced_settings}
          myself={@myself}
        />

        <.adapter_card
          adapter_name="Adapter 2"
          adapter_color="green"
          connected={@adapter_2_connected}
          device={@adapter_2_device}
          available_devices={@available_devices}
          settings={@adapter_2_settings}
          settings_changed={@adapter_2_settings_changed}
          adapter_key={:adapter_2}
          show_advanced={@show_advanced_settings}
          myself={@myself}
        />
      </div>

      <!-- Auto-Detection Section -->
      <%= if @adapter_1_connected && @adapter_2_connected do %>
        <div class="bg-teal-900/20 border border-teal-700 rounded-lg p-6 mb-3">
          <h4 class="text-lg font-semibold text-teal-300 mb-4">Auto-Detection & Naming</h4>
          <p class="text-sm text-neutral-300">
            We need to know which adapter goes to your controller and which goes to your amp. This tool determines which one is which for you.
          </p>

          <!-- Adapter Names - Only show after auto-detection is complete -->
          <%= if @adapter_1_role && @adapter_2_role && @adapter_1_role != "" && @adapter_2_role != "" do %>
            <div class="grid grid-cols-2 gap-4 mb-4">
              <div>
                <label class="block text-sm font-medium text-neutral-300 mb-2">Adapter 1 Name</label>
                <input
                  type="text"
                  value={@adapter_1_name}
                  phx-blur="update_adapter_name"
                  phx-target={@myself}
                  phx-value-adapter="adapter_1"
                  class="w-full px-3 py-2 bg-neutral-500 border border-neutral-400 rounded-md text-neutral-100 focus:outline-none focus:ring-2 focus:ring-teal-500"
                  placeholder="Enter name for Adapter 1"
                />
                <p class="text-xs text-neutral-400 mt-1">Detected as: <span class="text-green-400"><%= String.capitalize(@adapter_1_role || "") %></span></p>
              </div>
              <div>
                <label class="block text-sm font-medium text-neutral-300 mb-2">Adapter 2 Name</label>
                <input
                  type="text"
                  value={@adapter_2_name}
                  phx-blur="update_adapter_name"
                  phx-target={@myself}
                  phx-value-adapter="adapter_2"
                  class="w-full px-3 py-2 bg-neutral-500 border border-neutral-400 rounded-md text-neutral-100 focus:outline-none focus:ring-2 focus:ring-teal-500"
                  placeholder="Enter name for Adapter 2"
                />
                <p class="text-xs text-neutral-400 mt-1">Detected as: <span class="text-green-400"><%= String.capitalize(@adapter_2_role || "") %></span></p>
              </div>
            </div>
          <% else %>
            <!-- Show auto-detection prompt when adapters are connected but not detected -->
                  <ol>
                    <li>Click "Start Auto-Detection" below</li>
                    <li>Open up the ELAN/NICE app and perform an action like changing the volume</li>
                    <li>Alternatively, use a device connected to your controller that has the ability to do things like change the volume</li>
                    <li>If auto-detection fails, you may have a wiring issue.</li>
                  </ol>
          <% end %>

          <!-- Role Assignment Display -->
          <%= if @adapter_1_role && @adapter_2_role && @adapter_1_role != "" && @adapter_2_role != "" do %>
            <div class="mb-4 p-4 bg-green-900/20 border border-green-700 rounded-lg">
              <h5 class="text-sm font-medium text-green-300 mb-2">Detected Roles:</h5>
              <div class="grid grid-cols-2 gap-4">
                <div class="flex items-center space-x-2">
                  <div class="w-3 h-3 bg-blue-500 rounded-full"></div>
                  <span class="text-sm text-neutral-300">
                    <strong><%= @adapter_1_name %></strong>:
                    <span class="text-green-400"><%= String.capitalize(@adapter_1_role || "") %></span>
                  </span>
                </div>
                <div class="flex items-center space-x-2">
                  <div class="w-3 h-3 bg-green-500 rounded-full"></div>
                  <span class="text-sm text-neutral-300">
                    <strong><%= @adapter_2_name %></strong>:
                    <span class="text-green-400"><%= String.capitalize(@adapter_2_role || "") %></span>
                  </span>
                </div>
              </div>
            </div>
          <% end %>

          <!-- Action Buttons -->
          <div class="flex space-x-3">
            <%= if is_nil(@adapter_1_role) || is_nil(@adapter_2_role) || @adapter_1_role == "" || @adapter_2_role == "" do %>
              <!-- Show auto-detection button when roles not yet detected -->
              <%= if not @auto_detection_active do %>
                <button
                  phx-click="start_auto_detection"
                  phx-target={@myself}
                  class="px-6 py-3 bg-teal-600 hover:bg-teal-700 text-white rounded-md font-medium transition-colors flex items-center space-x-2"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
                  </svg>
                  <span>Start Auto-Detection</span>
                </button>
              <% else %>
                <button
                  phx-click="stop_auto_detection"
                  phx-target={@myself}
                  class="px-6 py-3 bg-red-600 hover:bg-red-700 text-white rounded-md font-medium transition-colors flex items-center space-x-2"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                  <span>Stop Auto-Detection</span>
                </button>
              <% end %>
            <% else %>
              <!-- Show completion message after detection is complete -->
              <div class="flex items-center space-x-2 text-green-400">
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                </svg>
                <span class="font-medium">Configuration Complete!</span>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
