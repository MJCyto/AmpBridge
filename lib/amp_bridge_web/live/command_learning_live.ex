defmodule AmpBridgeWeb.CommandLearningLive do
  @moduledoc """
  LiveView for command learning page.

  This page allows users to learn amplifier commands after initial setup.
  It renders the CommandLearningComponent for easy access to command learning functionality.
  """
  use AmpBridgeWeb, :live_view
  require Logger

  alias AmpBridgeWeb.CommandLearningComponent
  alias AmpBridge.Devices
  import AmpBridgeWeb.PageWrapper

  @impl true
  def mount(_params, _session, socket) do
    amp_id = 1
    device = Devices.get_device(amp_id)

    if device do
      {:ok,
       assign(socket,
         amp_id: amp_id,
         device: device,
         last_command_learned: nil
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, "No amplifier device found. Please run the initialization process first.")
       |> assign(amp_id: amp_id, device: nil, last_command_learned: nil)
      }
    end
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, uri: uri)}
  end

  @impl true
  def handle_info({:command_learned, device_id, control_type, zone}, socket) do
    Logger.info("Command learned: #{control_type} for zone #{zone}")

    {:noreply,
     assign(socket,
       last_command_learned: %{
         device_id: device_id,
         control_type: control_type,
         zone: zone,
         timestamp: DateTime.utc_now()
       }
     )
     |> put_flash(:info, "Successfully learned #{control_type} command for zone #{zone + 1}")
    }
  end

  @impl true
  def handle_info(msg, socket) do
    Logger.debug("CommandLearningLive received unhandled message: #{inspect(msg)}")
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page_wrapper uri={@uri}>
      <div class="space-y-6">
        <%= if @device do %>
          <!-- Command Learning Component -->
          <.live_component
            module={CommandLearningComponent}
            id="command-learning"
            amp_id={@amp_id}
            last_command_learned={@last_command_learned}
          />
        <% else %>
          <!-- No Device Found -->
          <div class="bg-red-900/20 border border-red-600 rounded-lg p-8 text-center">
            <div class="mx-auto flex items-center justify-center h-12 w-12 rounded-full bg-red-900/20 mb-4">
              <svg class="h-6 w-6 text-red-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z" />
              </svg>
            </div>
            <h3 class="text-lg font-medium text-red-300 mb-2">No Amplifier Device Found</h3>
            <p class="text-red-400 mb-6">
              Please run the initialization process first to configure your amplifier device.
            </p>
            <.link
              navigate={~p"/init"}
              class="bg-blue-600 hover:bg-blue-700 text-white px-6 py-2 rounded-md font-medium transition-colors"
            >
              Go to Initialization
            </.link>
          </div>
        <% end %>
      </div>
    </.page_wrapper>
    """
  end
end
