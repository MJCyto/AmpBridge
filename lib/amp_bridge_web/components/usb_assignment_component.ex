defmodule AmpBridgeWeb.USBAssignmentComponent do
  use AmpBridgeWeb, :live_component
  require Logger

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    # Get available USB devices
    devices = AmpBridge.USBDeviceScanner.get_devices()

    # Get current assignment for this amp
    amp_id = assigns.amp_id
    assigned_device = AmpBridge.USBDeviceScanner.get_amp_device_assignment(amp_id)

    socket =
      assign(socket,
        devices: devices,
        assigned_device: assigned_device,
        amp_id: amp_id
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("rescan_devices", _params, socket) do
    Logger.info("Re-scanning for USB devices")
    devices = AmpBridge.USBDeviceScanner.rescan_devices()

    {:noreply, assign(socket, devices: devices)}
  end

  @impl true
  def handle_event("assign_device", %{"device_path" => device_path, "amp_id" => amp_id}, socket) do
    amp_id = String.to_integer(amp_id)

    case AmpBridge.USBDeviceScanner.assign_device_to_amp(device_path, amp_id) do
      {:ok, _} ->
        # Update the assigned device in the socket
        {:noreply, assign(socket, assigned_device: device_path)}

      {:error, reason} ->
        Logger.error("Failed to assign device: #{reason}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("unassign_device", %{"amp_id" => amp_id}, socket) do
    amp_id = String.to_integer(amp_id)

    case AmpBridge.USBDeviceScanner.unassign_device_from_amp(amp_id) do
      {:ok, _} ->
        # Update the assigned device in the socket to nil
        {:noreply, assign(socket, assigned_device: nil)}

      {:error, reason} ->
        Logger.error("Failed to unassign device: #{reason}")
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="rounded-lg shadow-lg p-6 mb-6 border border-neutral-600">
      <div class="flex justify-between items-center mb-4">
        <div>
          <h3 class="text-lg font-semibold text-neutral-100">USB Device Assignment</h3>
          <p class="text-sm text-neutral-400">Connect and assign a USB-to-serial adapter for your amplifier</p>
        </div>
        <button phx-click="rescan_devices" phx-target={@myself} class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-md text-sm font-medium">
          Re-scan Devices
        </button>
      </div>

      <div class="text-sm text-neutral-400 mb-4">
        Last scan: <%= format_datetime(DateTime.utc_now()) %>
      </div>

      <%= if Enum.empty?(@devices) do %>
        <div class="text-center py-8 text-neutral-400">
          <div class="mb-4">
            <svg class="mx-auto h-12 w-12 text-neutral-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
            </svg>
          </div>
          <p class="font-medium">No USB devices found</p>
          <p class="text-sm mt-2">Make sure your USB-to-serial adapter is connected and try re-scanning</p>
        </div>
      <% else %>
        <div class="space-y-3">
          <%= for device <- @devices do %>
            <div class="border border-neutral-600 rounded-lg p-4 hover:bg-neutral-700">
              <div class="flex justify-between items-center">
                <div class="flex-1">
                  <div class="flex items-center space-x-3">
                    <div class="w-3 h-3 bg-green-500 rounded-full"></div>
                    <div>
                      <h4 class="font-medium text-neutral-100"><%= device.name %></h4>
                      <p class="text-sm text-neutral-400"><%= device.description %></p>
                      <p class="text-xs text-neutral-500 font-mono"><%= device.path %></p>
                    </div>
                  </div>
                </div>

                <div class="flex items-center space-x-3">
                  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-900 text-blue-200">
                    <%= device.type %>
                  </span>

                  <%= if @assigned_device == device.path do %>
                    <div class="flex items-center space-x-2">
                      <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-900 text-green-200">
                        Currently Assigned
                      </span>
                      <button phx-click="unassign_device" phx-target={@myself} phx-value-amp_id={@amp_id} class="bg-red-600 hover:bg-red-700 text-white px-2 py-1 rounded text-xs font-medium">
                        Unassign
                      </button>
                    </div>
                  <% else %>
                    <button phx-click="assign_device" phx-target={@myself} phx-value-device_path={device.path} phx-value-amp_id={@amp_id} class="bg-green-600 hover:bg-green-700 text-white px-3 py-1 rounded text-xs font-medium">
                      Assign Device
                    </button>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <div class="mt-6 p-4 bg-neutral-700 rounded-lg border border-neutral-600">
        <h4 class="text-sm font-medium text-neutral-100 mb-2">Current Status</h4>

        <%= if @assigned_device do %>
          <div class="flex items-center text-sm text-green-400">
            <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
            </svg>
            <span>USB device assigned: <span class="font-mono text-xs"><%= @assigned_device %></span></span>
          </div>
        <% else %>
          <div class="flex items-center text-sm text-yellow-400">
            <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z" />
            </svg>
            <span>No USB device assigned - connect an adapter and assign it above</span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
  end
end
