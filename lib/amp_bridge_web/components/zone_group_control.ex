defmodule AmpBridgeWeb.ZoneGroupControl do
  use Phoenix.LiveComponent
  require Logger

  alias AmpBridge.ZoneGroupManager

  attr(:group_id, :integer, required: true, doc: "Zone group ID")
  attr(:group_name, :string, required: true, doc: "Zone group name")
  attr(:group_description, :string, doc: "Zone group description")
  attr(:zones, :list, required: true, doc: "List of zones in this group")
  attr(:sources, :list, required: true, doc: "List of available sources")
  attr(:adapter_connected, :boolean, required: true, doc: "Whether the adapter is connected")
  attr(:myself, :any, default: nil, doc: "Component ID for phx-target")

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    # Get current group state
    group_state = case ZoneGroupManager.get_group_state(assigns.group_id) do
      {:ok, state} -> state
      {:error, _} -> %{muted: false, source: "Off", volume: 50, zone_count: 0}
    end

    # Get zone names for the zones in this group
    zone_names = get_zone_names_for_group(assigns.zones)

    {:ok, assign(socket, Map.merge(assigns, %{group_state: group_state, zone_names: zone_names}))}
  end

  @impl true
  def handle_event("group_volume_change", %{"volume" => volume}, socket) do
    group_id = socket.assigns.group_id
    volume_num = String.to_integer(volume)

    Logger.info("ZoneGroupControl: Group volume changed for group #{group_id} to #{volume_num}%")

    # Send command to ZoneGroupManager
    ZoneGroupManager.set_group_volume(group_id, volume_num)

    # Update local state
    {:noreply, assign(socket, group_state: Map.put(socket.assigns.group_state, :volume, volume_num))}
  end

  @impl true
  def handle_event("group_mute_toggle", _params, socket) do
    group_id = socket.assigns.group_id
    current_mute = socket.assigns.group_state.muted

    Logger.info("ZoneGroupControl: Group mute toggle for group #{group_id}, currently #{current_mute}")

    # Send command to ZoneGroupManager
    ZoneGroupManager.toggle_group_mute(group_id)

    # Don't update local state immediately - let the parent LiveView handle the refresh
    # when it receives the zone_mute_changed events
    {:noreply, socket}
  end

  @impl true
  def handle_event("group_source_change", %{"source" => source}, socket) do
    group_id = socket.assigns.group_id

    Logger.info("ZoneGroupControl: Group source changed for group #{group_id} to #{source}")

    # Send command to ZoneGroupManager
    ZoneGroupManager.set_group_source(group_id, source)

    # Update local state
    {:noreply, assign(socket, group_state: Map.put(socket.assigns.group_state, :source, source))}
  end


  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-neutral-800 rounded-lg p-4 min-w-[280px]">
      <!-- Group Header -->
      <div class="flex justify-between items-center mb-4">
        <div>
          <h4 class="text-lg font-semibold text-neutral-200"><%= @group_name %></h4>
          <%= if @group_description do %>
            <p class="text-sm text-neutral-400"><%= @group_description %></p>
          <% end %>
        </div>
        <div class="flex items-center gap-2 text-sm text-neutral-400">
          <span><%= length(@zones) %> zones</span>
          <div class="relative inline-block group">
            <svg class="w-4 h-4 text-neutral-500 cursor-help hover:text-neutral-300 transition-colors" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-8-3a1 1 0 00-.867.5 1 1 0 11-1.731-1A3 3 0 0113 8a3.001 3.001 0 01-2 2.83V11a1 1 0 11-2 0v-1a1 1 0 011-1 1 1 0 100-2zm0 8a1 1 0 100-2 1 1 0 000 2z" clip-rule="evenodd"></path>
            </svg>
            <div class="absolute bottom-full left-1/2 transform -translate-x-1/2 mb-2 px-3 py-2 bg-gray-900 text-white text-sm rounded-lg shadow-xl opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all duration-200 whitespace-nowrap z-50 border border-gray-700">
              <%= Enum.join(@zone_names, ", ") %>
              <div class="absolute top-full left-1/2 transform -translate-x-1/2 w-0 h-0 border-l-4 border-r-4 border-t-4 border-transparent border-t-gray-900"></div>
            </div>
          </div>
        </div>
      </div>

      <!-- Group Controls -->
      <div class="space-y-4">
        <!-- Volume Control -->
        <div>
          <div class="flex justify-between items-center mb-2">
            <label class="text-sm font-medium text-neutral-300">Volume</label>
            <span class="text-sm text-neutral-400"><%= @group_state.volume %>%</span>
          </div>
          <form phx-change="group_volume_change" phx-target={@myself}>
            <input
              id={"group-volume-slider-#{@group_id}"}
              name="volume"
              type="range"
              min="0"
              max="100"
              value={@group_state.volume}
              step="1"
              disabled={!@adapter_connected}
              class={[
                "w-full h-2 bg-neutral-700 rounded-lg appearance-none cursor-pointer slider",
                if(!@adapter_connected,
                  do: "opacity-50 cursor-not-allowed",
                  else: ""
                )
              ]}
              style="background: linear-gradient(to right, #3b82f6 0%, #3b82f6 50%, #374151 50%, #374151 100%);"
            />
          </form>
        </div>

        <!-- Mute Control -->
        <div class="flex justify-between items-center">
          <label class="text-sm font-medium text-neutral-300">Mute</label>
          <button
            phx-click="group_mute_toggle"
            phx-target={@myself}
            disabled={!@adapter_connected}
            class={[
              "p-2 rounded-lg transition-colors",
              if(@group_state.muted,
                do: "bg-red-600 hover:bg-red-700 text-white",
                else: "bg-neutral-600 hover:bg-neutral-500 text-neutral-200"
              ),
              if(!@adapter_connected,
                do: "opacity-50 cursor-not-allowed",
                else: ""
              )
            ]}
          >
            <%= if @group_state.muted do %>
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.536 8.464a5 5 0 010 7.072m2.828-9.9a9 9 0 010 12.728M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z"></path>
              </svg>
            <% else %>
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z"></path>
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2"></path>
              </svg>
            <% end %>
          </button>
        </div>

        <!-- Source Control -->
        <div>
          <label class="block text-sm font-medium text-neutral-300 mb-2">Source</label>
          <form phx-change="group_source_change" phx-target={@myself}>
            <select
              name="source"
              disabled={!@adapter_connected}
              class={[
                "w-full bg-neutral-700 border border-neutral-600 text-neutral-100 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500",
                if(!@adapter_connected,
                  do: "opacity-50 cursor-not-allowed",
                  else: ""
                )
              ]}
            >
              <option value="Off" selected={@group_state.source == "Off"}>Off</option>
              <%= for {source_name, index} <- Enum.with_index(@sources) do %>
                <option value={"Source #{index + 1}"} selected={@group_state.source == "Source #{index + 1}"}>
                  <%= source_name %>
                </option>
              <% end %>
            </select>
          </form>
        </div>

      </div>
    </div>
    """
  end

  # Helper function to get zone names for the zones in this group
  defp get_zone_names_for_group(zones) do
    try do
      device = AmpBridge.Devices.get_device(1)

      if device && device.zones && map_size(device.zones) > 0 do
        zones_map = device.zones

        zones
        |> Enum.map(fn zone_membership ->
          zone_index = zone_membership.zone_index
          get_zone_name(zones_map, zone_index)
        end)
        |> Enum.map(fn zone_name ->
          zone_name || "Unknown Zone"
        end)
      else
        # Fallback to generic names if no device configuration
        zones
        |> Enum.map(fn zone_membership ->
          "Zone #{zone_membership.zone_index + 1}"
        end)
      end
    rescue
      _error ->
        # Fallback to generic names on error
        zones
        |> Enum.map(fn zone_membership ->
          "Zone #{zone_membership.zone_index + 1}"
        end)
    end
  end

  defp get_zone_name(zones_map, zone_index) do
    # Get the configured zone numbers and sort them
    configured_zones = zones_map
    |> Map.keys()
    |> Enum.map(&String.to_integer/1)
    |> Enum.sort()

    # Map 0-based zone index to the corresponding configured zone number
    case Enum.at(configured_zones, zone_index) do
      nil -> nil
      zone_number ->
        case Map.get(zones_map, to_string(zone_number)) do
          %{"name" => name} when is_binary(name) and name != "" -> name
          _ -> nil
        end
    end
  end
end
