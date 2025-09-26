defmodule AmpBridgeWeb.ZoneSetupLive do
  use AmpBridgeWeb, :live_view
  require Logger

  alias AmpBridge.Devices
  alias AmpBridgeWeb.ZoneConfigComponent
  import AmpBridgeWeb.PageWrapper

  @impl true
  def mount(_params, _session, socket) do
    amp_id = 1

    # Load existing device configuration
    device = Devices.get_device(amp_id)
    zones = load_zones_from_device(device)
    sources = load_sources_from_device(device)

    {:ok,
     assign(socket,
       page_title: "Zone Setup",
       amp_id: amp_id,
       zones: zones,
       sources: sources
     )}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, uri: uri)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page_wrapper uri={@uri}>
      <div class="space-y-6">
        <div class="bg-neutral-700 rounded-lg shadow-lg border border-neutral-600">
          <div class="p-6">
            <div class="mb-6">
              <h1 class="text-2xl font-semibold text-neutral-100 mb-2">Zone Setup</h1>
              <p class="text-neutral-400">Configure your amplifier's audio zones and speaker groups.</p>
            </div>

            <.live_component
              module={ZoneConfigComponent}
              id="zone-config"
              amp_id={@amp_id}
              zones={@zones}
              sources={@sources}
            />
          </div>
        </div>
      </div>
    </.page_wrapper>
    """
  end

  defp load_zones_from_device(device) do
    case device do
      nil -> []
      device ->
        case device.zones do
          nil -> []
          zones_map when is_map(zones_map) ->
            zones_map
            |> Map.values()
            |> Enum.sort_by(& &1["index"])
          _ -> []
        end
    end
  end

  defp load_sources_from_device(device) do
    case device do
      nil -> []
      device ->
        case device.sources do
          nil -> []
          sources_map when is_map(sources_map) ->
            sources_map
            |> Map.values()
            |> Enum.sort_by(& &1["index"])
          _ -> []
        end
    end
  end
end
