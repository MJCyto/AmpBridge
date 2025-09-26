defmodule AmpBridgeWeb.ZoneVolumeControl do
  use Phoenix.LiveComponent
  require Logger
  attr(:zone, :integer,
    required: true,
    doc: "Zone number (0-based internally, displayed as 1-based)"
  )

  attr(:zone_name, :string,
    doc: "Optional zone name. If provided, replaces 'Zone X' in the title"
  )

  attr(:adapter_connected, :boolean, required: true, doc: "Whether the adapter is connected")
  attr(:adapter, :string, required: true, doc: "Adapter name (adapter_1, adapter_2, etc.)")
  attr(:mute, :boolean, default: false, doc: "Whether the zone is currently muted")
  attr(:volume, :integer, default: 50, doc: "Current volume level (0-100)")
  attr(:sources, :list, default: [], doc: "List of available sources for this zone")
  attr(:current_source, :string, default: "Off", doc: "Currently selected source")
  attr(:myself, :any, default: nil, doc: "Component ID for phx-target")

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("volume_slider_change", %{"volume" => volume}, socket) do
    zone = socket.assigns.zone
    volume_num = String.to_integer(volume)

    Logger.info("ZoneVolumeControl: Volume slider changed for zone #{zone} to #{volume_num}%")

    send(self(), {:zone_volume_change, zone, volume_num})
    {:noreply, assign(socket, volume: volume_num)}
  end

  @impl true
  def handle_event("mute_toggle", _params, socket) do
    zone = socket.assigns.zone
    current_mute = socket.assigns.mute

    Logger.info("ZoneVolumeControl: Mute toggle for zone #{zone}, currently #{current_mute}")

    send(self(), {:zone_mute_toggle, zone})
    {:noreply, assign(socket, mute: !current_mute)}
  end

  @impl true
  def handle_event("source_change", %{"source" => source}, socket) do
    zone = socket.assigns.zone

    Logger.info("ZoneVolumeControl: Source change for zone #{zone} to #{source}")

    send(self(), {:zone_source_change, zone, source})
    {:noreply, assign(socket, current_source: source)}
  end

  @impl true
  def handle_event("volume_button_click", %{"command" => command}, socket) do
    zone = socket.assigns.zone

    Logger.info("ZoneVolumeControl: Volume button #{command} for zone #{zone}")

    send(self(), {:zone_volume_button, zone, command})
    {:noreply, socket}
  end

  def zone_volume_control(assigns) do
    render(assigns)
  end

  @impl true
  def render(assigns) do
    assigns = assign_new(assigns, :zone_name, fn -> nil end)

    ~H"""
    <div id={"zone-control-#{@zone}"} class="bg-neutral-600 rounded-lg p-2 border border-neutral-500 flex-shrink-0">
      <div class="flex items-center justify-between mb-2 relative">
        <h4 class="text-lg font-semibold text-neutral-200">
          <%= if @zone_name do %>
            <%= @zone_name %>
          <% else %>
            Zone <%= @zone + 1 %>
          <% end %>
        </h4>

        <div class="absolute left-1/2 transform -translate-x-1/2">
          <span class="text-sm text-neutral-300 font-mono" id={"volume-display-#{@zone}"}><%= @volume %>%</span>
        </div>
        <button
          phx-click="mute_toggle"
          phx-target={@myself}
          disabled={!@adapter_connected}
          aria-label={if @mute, do: "Unmute zone #{@zone + 1}", else: "Mute zone #{@zone + 1}"}
          aria-pressed={@mute}
          class={[
            "px-3 py-2 rounded-md text-sm font-medium transition-colors flex items-center justify-center",
            if(!@adapter_connected,
              do: "bg-neutral-500 text-neutral-300 cursor-not-allowed",
              else: if(@mute,
                do: "bg-yellow-600 text-white hover:bg-yellow-700",
                else: "bg-red-600 text-white hover:bg-red-700"
              )
            )
          ]}
        >
          <%= if @mute do %>
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

      <div class="mb-2">
        <form phx-change="volume_slider_change" phx-target={@myself}>
          <input
            id={"volume-slider-#{@zone}"}
            name="volume"
            type="range"
            min="0"
            max="100"
            value={@volume}
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

      <div class="mb-2">
        <form phx-change="source_change" phx-target={@myself}>
          <select
            name="source"
            disabled={!@adapter_connected}
            class={[
              "w-full px-2 py-1 text-sm rounded border bg-neutral-700 text-neutral-200",
              if(!@adapter_connected,
                do: "opacity-50 cursor-not-allowed",
                else: "hover:bg-neutral-600 focus:ring-2 focus:ring-blue-500"
              )
            ]}
          >
            <option value="Off" selected={@current_source == "Off" || @current_source == nil}>Off</option>
            <%= for {source_name, index} <- Enum.with_index(@sources) do %>
              <option value={"Source #{index + 1}"} selected={@current_source == "Source #{index + 1}"}>
                <%= source_name %>
              </option>
            <% end %>
          </select>
        </form>
      </div>

    </div>
    """
  end
end
