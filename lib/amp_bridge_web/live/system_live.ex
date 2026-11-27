defmodule AmpBridgeWeb.SystemLive do
  use AmpBridgeWeb, :live_view
  alias AmpBridge.Devices
  alias AmpBridge.SerialManager
  import AmpBridgeWeb.PageWrapper

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_status(socket)}
  end

  @impl true
  def handle_params(_params, uri, socket), do: {:noreply, assign(socket, uri: uri)}

  @impl true
  def handle_event("refresh_status", _params, socket), do: {:noreply, assign_status(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <.page_wrapper uri={@uri}>
      <div class="space-y-6">
        <div class="bg-neutral-700 rounded-lg shadow-lg border border-neutral-600 p-6">
          <div class="flex items-center justify-between mb-6">
            <h1 class="text-2xl font-semibold text-neutral-100">System</h1>
            <button phx-click="refresh_status" class="rounded bg-teal-600 px-3 py-2 text-sm text-white hover:bg-teal-700">Refresh</button>
          </div>
          <div class="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3">
            <.status_card title="Serial Adapters" healthy={@adapter_1_connected && @adapter_2_connected}>
              <.status_row label="Adapter 1" value={if @adapter_1_connected, do: "Connected", else: "Disconnected"} healthy={@adapter_1_connected} />
              <.status_row label="Adapter 2" value={if @adapter_2_connected, do: "Connected", else: "Disconnected"} healthy={@adapter_2_connected} />
              <.status_row label="Relay" value={if @adapter_1_connected && @adapter_2_connected, do: "Active", else: "Waiting"} healthy={@adapter_1_connected && @adapter_2_connected} />
            </.status_card>
            <.status_card title="Database" healthy={@database_connected}>
              <.status_row label="Status" value={if @database_connected, do: "Connected", else: "Error"} healthy={@database_connected} />
              <.status_row label="Type" value="SQLite" />
              <.status_row label="Devices" value={to_string(@device_count)} />
            </.status_card>
            <.status_card title="MQTT" healthy={@mqtt_connected}>
              <.status_row label="Status" value={if @mqtt_connected, do: "Connected", else: "Disconnected"} healthy={@mqtt_connected} />
              <.status_row label="Broker" value={@mqtt_broker || "Not configured"} />
              <.status_row label="Messages" value={to_string(@mqtt_message_count || 0)} />
            </.status_card>
          </div>
          <div class="mt-6 border-t border-neutral-600 pt-4">
            <h2 class="mb-3 text-sm font-medium text-neutral-300">System Details</h2>
            <div class="grid grid-cols-1 gap-3 text-sm md:grid-cols-2">
              <.status_row label="System uptime" value={@system_uptime} />
              <.status_row label="Memory usage" value={@memory_usage} />
              <.status_row label="Last command" value={@last_command_details} />
              <.status_row label="Error count" value={to_string(@error_count || 0)} />
            </div>
          </div>
        </div>
      </div>
    </.page_wrapper>
    """
  end

  attr(:title, :string, required: true)
  attr(:healthy, :boolean, required: true)
  slot(:inner_block, required: true)

  defp status_card(assigns) do
    ~H"""
    <div class="rounded-lg bg-neutral-800 p-4">
      <div class="mb-3 flex items-center justify-between">
        <h2 class="text-sm font-medium text-neutral-300"><%= @title %></h2>
        <span class={if @healthy, do: "text-green-400", else: "text-yellow-400"}><%= if @healthy, do: "●", else: "!" %></span>
      </div>
      <div class="space-y-2"><%= render_slot(@inner_block) %></div>
    </div>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :string, required: true)
  attr(:healthy, :boolean, default: true)

  defp status_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-3">
      <span class="text-neutral-400"><%= @label %></span>
      <span class={if Map.get(assigns, :healthy, true), do: "text-green-400", else: "text-red-400"}><%= @value %></span>
    </div>
    """
  end

  defp assign_status(socket) do
    connection_status = SerialManager.get_connection_status()
    status = AmpBridge.SystemStatus.fetch()

    assign(
      socket,
      Map.merge(status, %{
        page_title: "System",
        adapter_1_connected: connection_status.adapter_1.connected,
        adapter_2_connected: connection_status.adapter_2.connected,
        device_count: length(Devices.list_devices())
      })
    )
  end
end
