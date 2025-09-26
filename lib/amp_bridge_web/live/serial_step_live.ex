defmodule AmpBridgeWeb.SerialStepLive do
  use AmpBridgeWeb, :live_view
  require Logger

  alias AmpBridge.Devices
  alias AmpBridge.SerialManager
  alias AmpBridgeWeb.USBInitComponent
  import AmpBridgeWeb.PageWrapper

  @impl true
  def mount(_params, _session, socket) do
    amp_id = 1

    # Get connection status
    connection_status = SerialManager.get_connection_status()

    {:ok,
     assign(socket,
       page_title: "Serial Step",
       amp_id: amp_id,
       # Auto-detection state
       auto_detection_active: false,
       adapter_1_name: "Controller",
       adapter_2_name: "Amp",
       adapter_1_role: nil,
       adapter_2_role: nil,
       detection_status: "Ready to start auto-detection",
       adapter_1_connected: connection_status.adapter_1.connected,
       adapter_2_connected: connection_status.adapter_2.connected
     )}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, uri: uri)}
  end

  @impl true
  def handle_info({:start_auto_detection, _amp_id}, socket) do
    Logger.info("Starting auto-detection for serial step")
    Phoenix.PubSub.subscribe(AmpBridge.PubSub, "serial_data")
    {:noreply, put_flash(socket, :info, "Auto-detection started - send commands from your controller")}
  end

  @impl true
  def handle_info({:stop_auto_detection, _amp_id}, socket) do
    Logger.info("Stopping auto-detection for serial step")
    Phoenix.PubSub.unsubscribe(AmpBridge.PubSub, "serial_data")
    {:noreply, put_flash(socket, :info, "Auto-detection stopped")}
  end

  @impl true
  def handle_info({:save_adapter_roles, _amp_id}, socket) do
    Logger.info("Received save adapter roles request for serial step")

    case Devices.get_device(1) do
      nil ->
        {:noreply, put_flash(socket, :error, "Device not found")}

      device ->
        attrs = %{
          auto_detection_complete: true,
          adapter_1_role: "controller",
          adapter_2_role: "amp"
        }

        case Devices.update_device(device, attrs) do
          {:ok, _updated_device} ->
            Logger.info("Adapter roles saved successfully for serial step")
            {:noreply, put_flash(socket, :info, "Adapter roles saved! Auto-detection complete.")}

          {:error, changeset} ->
            Logger.error("Failed to save adapter roles for serial step: #{inspect(changeset)}")
            {:noreply, put_flash(socket, :error, "Failed to save adapter roles")}
        end
    end
  end

  @impl true
  def handle_info({:update_adapter_name, adapter, name}, socket) do
    Logger.info("Received adapter name update for serial step: #{adapter} -> #{name}")

    case Devices.get_device(1) do
      nil ->
        {:noreply, put_flash(socket, :error, "Device not found")}

      device ->
        field = if adapter == "adapter_1", do: :adapter_1_name, else: :adapter_2_name
        attrs = %{field => name}

        case Devices.update_device(device, attrs) do
          {:ok, _updated_device} ->
            Logger.info("Updated #{adapter} name to #{name} for serial step")
            {:noreply, put_flash(socket, :info, "#{String.capitalize(adapter)} name updated to #{name}")}

          {:error, changeset} ->
            Logger.error("Failed to update #{adapter} name for serial step: #{inspect(changeset)}")
            {:noreply, put_flash(socket, :error, "Failed to update #{adapter} name")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page_wrapper uri={@uri}>
      <div class="space-y-6">
        <div class="bg-neutral-700 rounded-lg shadow-lg border border-neutral-600">
          <div class="p-6">
            <div class="mb-6">
              <h1 class="text-2xl font-semibold text-neutral-100 mb-2">Serial Step</h1>
              <p class="text-neutral-400">Connect and configure USB-to-serial adapters for your amplifier.</p>
            </div>

            <.live_component
              module={USBInitComponent}
              id="usb-init-serial-step"
              amp_id={@amp_id}
              auto_detection_active={@auto_detection_active}
              adapter_1_name={@adapter_1_name}
              adapter_2_name={@adapter_2_name}
              adapter_1_role={@adapter_1_role}
              adapter_2_role={@adapter_2_role}
              detection_status={@detection_status}
            />
          </div>
        </div>
      </div>
    </.page_wrapper>
    """
  end
end
