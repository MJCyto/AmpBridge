defmodule AmpBridgeWeb.ZoneConfigComponent do
  use AmpBridgeWeb, :live_component
  require Logger

  alias AmpBridge.Devices

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    # Subscribe to real-time updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(AmpBridge.PubSub, "zone_config_updates")
    end

    # Load existing data from database
    {zones, form_data} = load_existing_zones(assigns.amp_id, assigns.sources)

    socket =
      assign(socket,
        form_data: form_data,
        errors: %{},
        zones: zones,
        sources: assigns.sources,
        amp_id: assigns.amp_id
      )

    {:ok, socket}
  end

  def handle_info({:zones_updated, zones}, socket) do
    form_data = Map.put(socket.assigns.form_data, "zones", zones)
    {:noreply, assign(socket, zones: zones, form_data: form_data)}
  end

  @impl true
  def handle_event("form_change", %{"zone_config" => form_data}, socket) do
    # Update form data and validate
    errors = validate_form(form_data)

    {:noreply, assign(socket, form_data: form_data, errors: errors)}
  end

  def handle_event("update_zone_count", %{"zone_config" => %{"zone_count" => count}}, socket) do
    if count == "" do
      form_data = Map.put(socket.assigns.form_data, "zone_count", "")
      # Broadcast the change
      Phoenix.PubSub.broadcast(AmpBridge.PubSub, "zone_config_updates", {:zones_updated, []})
      {:noreply, assign(socket, form_data: form_data, zones: [])}
    else
      count_int = String.to_integer(count)
      zones = generate_zones(count_int, socket.assigns.sources)

      form_data = Map.put(socket.assigns.form_data, "zone_count", count)
      form_data = Map.put(form_data, "zones", zones)

      # Save to database and broadcast
      zones_with_defaults = apply_zone_defaults(zones)
      save_zones_to_db(socket, zones_with_defaults)
      Phoenix.PubSub.broadcast(AmpBridge.PubSub, "zone_config_updates", {:zones_updated, zones})

      {:noreply, assign(socket, form_data: form_data, zones: zones)}
    end
  end

  def handle_event("update_zone_name", %{"index" => index, "value" => name}, socket) do
    index_int = String.to_integer(index)
    zones = socket.assigns.zones

    updated_zones =
      zones
      |> Enum.with_index()
      |> Enum.map(fn {zone, i} ->
        if i == index_int do
          Map.put(zone, "name", name)
        else
          zone
        end
      end)

    form_data = Map.put(socket.assigns.form_data, "zones", updated_zones)

    # Save to database and broadcast
    zones_with_defaults = apply_zone_defaults(updated_zones)
    save_zones_to_db(socket, zones_with_defaults)
    Phoenix.PubSub.broadcast(AmpBridge.PubSub, "zone_config_updates", {:zones_updated, updated_zones})

    {:noreply, assign(socket, form_data: form_data, zones: updated_zones)}
  end

  def handle_event("update_zone_sources", %{"index" => index, "sources" => selected_sources}, socket) do
    index_int = String.to_integer(index)
    zones = socket.assigns.zones

    # Convert selected sources to integers
    selected_indices =
      selected_sources
      |> Enum.map(&String.to_integer/1)
      |> Enum.sort()

    updated_zones =
      zones
      |> Enum.with_index()
      |> Enum.map(fn {zone, i} ->
        if i == index_int do
          Map.put(zone, "available_sources", selected_indices)
        else
          zone
        end
      end)

    form_data = Map.put(socket.assigns.form_data, "zones", updated_zones)

    # Save to database and broadcast
    zones_with_defaults = apply_zone_defaults(updated_zones)
    save_zones_to_db(socket, zones_with_defaults)
    Phoenix.PubSub.broadcast(AmpBridge.PubSub, "zone_config_updates", {:zones_updated, updated_zones})

    {:noreply, assign(socket, form_data: form_data, zones: updated_zones)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <form phx-submit="form_change" phx-target={@myself}>
        <div class="space-y-6">
          <!-- Zone Count Configuration -->
          <div>
            <label class="block text-sm font-medium text-neutral-300 mb-2">
              How many audio zones does your amplifier have?
            </label>
            <input
              type="number"
              name="zone_config[zone_count]"
              value={@form_data["zone_count"]}
              phx-blur="update_zone_count"
              phx-target={@myself}
              min="1"
              max="20"
              class={input_class(@errors["zone_count"])}
              placeholder="Enter number of zones (1-20)"
            />
            <%= if @errors["zone_count"] do %>
              <p class="mt-1 text-sm text-red-400"><%= @errors["zone_count"] %></p>
            <% end %>
          </div>

          <!-- Zone Names and Source Configuration -->
          <%= if length(@zones) > 0 do %>
            <div>
              <label class="block text-sm font-medium text-neutral-300 mb-3">
                Configure your zones:
              </label>
              <div class="space-y-6">
                <%= for {zone, index} <- Enum.with_index(@zones) do %>
                  <div class="bg-neutral-800 rounded-lg p-4">
                    <div class="flex items-center space-x-3 mb-3">
                      <label class="text-sm text-neutral-300 w-20">
                        Zone <%= index + 1 %>:
                      </label>
                      <input
                        type="text"
                        name={"zone_config[zones][#{index}][name]"}
                        value={zone["name"]}
                        phx-blur="update_zone_name"
                        phx-value-index={index}
                        phx-target={@myself}
                        class={input_class(@errors["zones_#{index}"])}
                        placeholder="Enter zone name (e.g., 'Living Room', 'Kitchen', 'Bedroom')"
                      />
                    </div>
                    <%= if @errors["zones_#{index}"] do %>
                      <p class="ml-24 text-sm text-red-400 mb-3"><%= @errors["zones_#{index}"] %></p>
                    <% end %>

                    <!-- Available Sources for this Zone -->
                    <%= if length(@sources) > 0 do %>
                      <div class="ml-24">
                        <label class="block text-sm text-neutral-400 mb-2">
                          Available sources for this zone:
                        </label>
                        <div class="flex flex-wrap gap-2">
                          <%= for {source, source_index} <- Enum.with_index(@sources) do %>
                            <label class="flex items-center space-x-2">
                              <input
                                type="checkbox"
                                name={"zone_config[zones][#{index}][sources][]"}
                                value={source_index}
                                checked={source_index in Map.get(zone, "available_sources", [])}
                                phx-change="update_zone_sources"
                                phx-value-index={index}
                                phx-target={@myself}
                                class="rounded border-neutral-600 bg-neutral-700 text-blue-600 focus:ring-blue-500"
                              />
                              <span class="text-sm text-neutral-300">
                                <%= source["name"] || "Source #{source_index + 1}" %>
                              </span>
                            </label>
                          <% end %>
                        </div>
                      </div>
                    <% else %>
                      <div class="ml-24 text-sm text-yellow-400">
                        No sources configured yet. Please set up sources first.
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </form>
    </div>
    """
  end

  defp input_class(error) do
    base_class = "w-full px-3 py-2 bg-neutral-800 text-neutral-100 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"

    if error do
      base_class <> " border-red-500"
    else
      base_class <> " border-neutral-600"
    end
  end

  defp generate_zones(count, sources) do
    source_indices = Enum.to_list(0..(length(sources) - 1))

    Enum.map(0..(count - 1), fn index ->
      %{
        "name" => "",
        "index" => index,
        "available_sources" => source_indices
      }
    end)
  end

  defp validate_form(_form_data) do
    %{}
  end

  defp load_existing_zones(amp_id, _sources) do
    case Devices.get_device(amp_id) do
      nil ->
        # No existing device - return empty data
        {[], %{"zones" => %{}, "zone_count" => ""}}

      device ->
        # Load existing zones
        zones = load_zones_from_device(device)

        form_data = %{
          "zones" => zones,
          "zone_count" => if(length(zones) > 0, do: to_string(length(zones)), else: "")
        }

        {zones, form_data}
    end
  end

  defp load_zones_from_device(device) do
    case device.zones do
      nil -> []
      zones_map when is_map(zones_map) ->
        zones_map
        |> Map.values()
        |> Enum.sort_by(& &1["index"])
      _ -> []
    end
  end

  defp apply_zone_defaults(zones) do
    zones
    |> Enum.with_index()
    |> Enum.map(fn {zone, index} ->
      name =
        if String.trim(zone["name"] || "") == "" do
          "Zone #{index + 1}"
        else
          zone["name"]
        end

      Map.put(zone, "name", name)
    end)
    |> Enum.with_index()
    |> Enum.into(%{}, fn {zone, index} -> {to_string(index), zone} end)
  end

  defp save_zones_to_db(socket, zones_with_defaults) do
    # Get the device and update with zones
    device_id = Map.get(socket.assigns, :amp_id, 1)

    case Devices.get_device(device_id) do
      nil ->
        # This shouldn't happen if sources were saved first, but handle it
        {:error, "Device not found"}

      device ->
        Devices.update_device(device, %{
          zones: zones_with_defaults
        })
    end
  end
end
