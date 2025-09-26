defmodule AmpBridgeWeb.SourceSetupLive do
  use AmpBridgeWeb, :live_view
  require Logger

  alias AmpBridge.Devices
  alias AmpBridgeWeb.SourceConfigComponent
  import AmpBridgeWeb.PageWrapper

  @impl true
  def mount(_params, _session, socket) do
    amp_id = 1

    # Load existing device configuration
    device = Devices.get_device(amp_id)
    sources = load_sources_from_device(device)

    {:ok,
     assign(socket,
       page_title: "Source Setup",
       amp_id: amp_id,
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
              <h1 class="text-2xl font-semibold text-neutral-100 mb-2">Source Setup</h1>
              <p class="text-neutral-400">Configure your amplifier's audio sources and inputs.</p>
            </div>

            <.live_component
              module={SourceConfigComponent}
              id="source-config"
              amp_id={@amp_id}
              sources={@sources}
            />
          </div>
        </div>
      </div>
    </.page_wrapper>
    """
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
