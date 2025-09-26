defmodule AmpBridgeWeb.AmpConfigComponent do
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
      Phoenix.PubSub.subscribe(AmpBridge.PubSub, "amp_config_updates")
    end

    # Load existing data from database
    {sources, zones, form_data} = load_existing_config(assigns.amp_id)

    socket =
      assign(socket,
        form_data: form_data,
        errors: %{},
        sources: sources,
        zones: zones,
        amp_id: assigns.amp_id
      )

    {:ok, socket}
  end

  def handle_info({:sources_updated, sources}, socket) do
    # Update zones to reflect new source count
    updated_zones = update_zones_for_sources(socket.assigns.zones, sources)
    form_data = Map.put(socket.assigns.form_data, "zones", updated_zones)

    {:noreply, assign(socket, sources: sources, zones: updated_zones, form_data: form_data)}
  end

  def handle_info({:zones_updated, zones}, socket) do
    form_data = Map.put(socket.assigns.form_data, "zones", zones)
    {:noreply, assign(socket, zones: zones, form_data: form_data)}
  end

  @impl true
  def handle_event("form_change", %{"amp_config" => form_data}, socket) do
    # Update form data and validate
    errors = validate_form(form_data)

    {:noreply, assign(socket, form_data: form_data, errors: errors)}
  end

  def handle_event("update_source_count", %{"amp_config" => %{"source_count" => count}}, socket) do
    if count == "" do
      form_data = Map.put(socket.assigns.form_data, "source_count", "")
      # Broadcast the change
      Phoenix.PubSub.broadcast(AmpBridge.PubSub, "amp_config_updates", {:sources_updated, []})
      {:noreply, assign(socket, form_data: form_data, sources: [])}
    else
      count_int = String.to_integer(count)
      sources = generate_sources(count_int)

      form_data = Map.put(socket.assigns.form_data, "source_count", count)
      form_data = Map.put(form_data, "sources", sources)

      # Save to database and broadcast
      save_sources_to_db(socket, sources)
      Phoenix.PubSub.broadcast(AmpBridge.PubSub, "amp_config_updates", {:sources_updated, sources})

      {:noreply, assign(socket, form_data: form_data, sources: sources)}
    end
  end

  def handle_event("update_zone_count", %{"amp_config" => %{"zone_count" => count}}, socket) do
    if count == "" do
      form_data = Map.put(socket.assigns.form_data, "zone_count", "")
      # Broadcast the change
      Phoenix.PubSub.broadcast(AmpBridge.PubSub, "amp_config_updates", {:zones_updated, []})
      {:noreply, assign(socket, form_data: form_data, zones: [])}
    else
      count_int = String.to_integer(count)
      zones = generate_zones(count_int, socket.assigns.sources)

      form_data = Map.put(socket.assigns.form_data, "zone_count", count)
      form_data = Map.put(form_data, "zones", zones)

      # Save to database and broadcast
      zones_with_defaults = apply_zone_defaults(zones)
      save_zones_to_db(socket, zones_with_defaults)
      Phoenix.PubSub.broadcast(AmpBridge.PubSub, "amp_config_updates", {:zones_updated, zones})

      {:noreply, assign(socket, form_data: form_data, zones: zones)}
    end
  end

  def handle_event("update_source_name", %{"index" => index, "value" => name}, socket) do
    index_int = String.to_integer(index)
    sources = List.update_at(socket.assigns.sources, index_int, &Map.put(&1, "name", name))
    form_data = Map.put(socket.assigns.form_data, "sources", sources)

    # Save to database and broadcast
    save_sources_to_db(socket, sources)
    Phoenix.PubSub.broadcast(AmpBridge.PubSub, "amp_config_updates", {:sources_updated, sources})

    {:noreply, assign(socket, form_data: form_data, sources: sources)}
  end

  def handle_event("update_zone_name", %{"index" => index, "value" => name}, socket) do
    index_int = String.to_integer(index)
    zones = List.update_at(socket.assigns.zones, index_int, &Map.put(&1, "name", name))
    form_data = Map.put(socket.assigns.form_data, "zones", zones)

    # Save to database and broadcast
    zones_with_defaults = apply_zone_defaults(zones)
    save_zones_to_db(socket, zones_with_defaults)
    Phoenix.PubSub.broadcast(AmpBridge.PubSub, "amp_config_updates", {:zones_updated, zones})

    {:noreply, assign(socket, form_data: form_data, zones: zones)}
  end

  def handle_event(
        "toggle_source_for_zone",
        %{"zone_index" => zone_index, "source_index" => source_index},
        socket
      ) do
    zone_index_int = String.to_integer(zone_index)
    source_index_int = String.to_integer(source_index)

    zones =
      List.update_at(socket.assigns.zones, zone_index_int, fn zone ->
        available_sources = Map.get(zone, "available_sources", [])

        if source_index_int in available_sources do
          Map.put(zone, "available_sources", List.delete(available_sources, source_index_int))
        else
          Map.put(zone, "available_sources", [source_index_int | available_sources])
        end
      end)

    form_data = Map.put(socket.assigns.form_data, "zones", zones)

    # Save to database and broadcast
    zones_with_defaults = apply_zone_defaults(zones)
    save_zones_to_db(socket, zones_with_defaults)
    Phoenix.PubSub.broadcast(AmpBridge.PubSub, "amp_config_updates", {:zones_updated, zones})

    {:noreply, assign(socket, form_data: form_data, zones: zones)}
  end

  def handle_event("add_source", _params, socket) do
    new_source = %{"name" => "New Source", "index" => length(socket.assigns.sources)}
    sources = socket.assigns.sources ++ [new_source]
    form_data = Map.put(socket.assigns.form_data, "sources", sources)

    # Save to database and broadcast
    save_sources_to_db(socket, sources)
    Phoenix.PubSub.broadcast(AmpBridge.PubSub, "amp_config_updates", {:sources_updated, sources})

    {:noreply, assign(socket, form_data: form_data, sources: sources)}
  end

  def handle_event("remove_source", %{"index" => index}, socket) do
    index_int = String.to_integer(index)
    sources = List.delete_at(socket.assigns.sources, index_int)
    # Reindex sources
    sources =
      Enum.with_index(sources) |> Enum.map(fn {source, idx} -> Map.put(source, "index", idx) end)

    form_data = Map.put(socket.assigns.form_data, "sources", sources)

    # Save to database and broadcast
    save_sources_to_db(socket, sources)
    Phoenix.PubSub.broadcast(AmpBridge.PubSub, "amp_config_updates", {:sources_updated, sources})

    {:noreply, assign(socket, form_data: form_data, sources: sources)}
  end

  def handle_event("add_zone", _params, socket) do
    new_zone = %{
      "name" => "New Zone",
      "index" => length(socket.assigns.zones),
      "available_sources" => Enum.to_list(0..(length(socket.assigns.sources) - 1))
    }

    zones = socket.assigns.zones ++ [new_zone]
    form_data = Map.put(socket.assigns.form_data, "zones", zones)

    # Save to database and broadcast
    zones_with_defaults = apply_zone_defaults(zones)
    save_zones_to_db(socket, zones_with_defaults)
    Phoenix.PubSub.broadcast(AmpBridge.PubSub, "amp_config_updates", {:zones_updated, zones})

    {:noreply, assign(socket, form_data: form_data, zones: zones)}
  end

  def handle_event("remove_zone", %{"index" => index}, socket) do
    index_int = String.to_integer(index)
    zones = List.delete_at(socket.assigns.zones, index_int)
    # Reindex zones
    zones = Enum.with_index(zones) |> Enum.map(fn {zone, idx} -> Map.put(zone, "index", idx) end)
    form_data = Map.put(socket.assigns.form_data, "zones", zones)

    # Save to database and broadcast
    zones_with_defaults = apply_zone_defaults(zones)
    save_zones_to_db(socket, zones_with_defaults)
    Phoenix.PubSub.broadcast(AmpBridge.PubSub, "amp_config_updates", {:zones_updated, zones})

    {:noreply, assign(socket, form_data: form_data, zones: zones)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="rounded-lg shadow-lg p-6 mb-6 border border-neutral-600">

      <form phx-change="form_change" phx-target={@myself}>
        <input type="hidden" name="amp_config[_form_name]" value="amp_config" />

        <!-- Sources Configuration Section -->
        <div class="mb-8">
          <h4 class="text-md font-medium text-neutral-100 mb-6">Audio Sources</h4>

          <!-- Number of Sources -->
          <div class="mb-6">
            <label for="source_count" class="block text-sm font-medium text-neutral-300 mb-1">How many audio sources do you have?</label>
            <select
              id="source_count"
              name="amp_config[source_count]"
              phx-change="update_source_count"
              phx-target={@myself}
              class={input_class(@errors["source_count"])}
            >
              <option value="" selected={@form_data["source_count"] == ""}>Select number of sources</option>
              <%= for count <- 1..8 do %>
                <option value={to_string(count)} selected={@form_data["source_count"] == to_string(count)}>
                  <%= count %>
                </option>
              <% end %>
            </select>
          </div>

          <!-- Source Names -->
          <%= if length(@sources) > 0 do %>
            <div class="mb-6">
              <h5 class="text-sm font-medium text-neutral-100 mb-4">Name your sources:</h5>
              <div class="space-y-3">
                <%= for {source, index} <- Enum.with_index(@sources) do %>
                  <div class="flex items-center space-x-3">
                    <div class="flex-1">
                      <input
                        type="text"
                        value={source["name"]}
                        phx-keyup="update_source_name"
                        phx-target={@myself}
                        phx-value-index={to_string(index)}
                        class={input_class(@errors["source_#{index}"])}
                        placeholder={"Source #{index + 1}"}
                      />
                      <%= if @errors["source_#{index}"] do %>
                        <p class="mt-1 text-sm text-red-400"><%= @errors["source_#{index}"] %></p>
                      <% end %>
                    </div>
                    <%= if length(@sources) > 1 do %>
                      <button
                        type="button"
                        phx-click="remove_source"
                        phx-target={@myself}
                        phx-value-index={to_string(index)}
                        class="p-2 text-red-400 hover:text-red-300 hover:bg-red-900/20 rounded-md"
                      >
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                        </svg>
                      </button>
                    <% end %>
                  </div>
                <% end %>
              </div>

              <button
                type="button"
                phx-click="add_source"
                phx-target={@myself}
                class="mt-3 inline-flex items-center px-3 py-2 border border-neutral-600 text-sm font-medium rounded-md text-neutral-300 bg-neutral-700 hover:bg-neutral-600"
              >
                <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                </svg>
                Add Source
              </button>
            </div>
          <% end %>
        </div>

        <!-- Zones Configuration Section (under sources) -->
        <%= if length(@sources) > 0 do %>
          <div class="mb-8 border-t border-neutral-600 pt-8">
            <h4 class="text-md font-medium text-neutral-100 mb-6">Audio Zones</h4>

            <!-- Number of Zones -->
            <div class="mb-6">
              <label for="zone_count" class="block text-sm font-medium text-neutral-300 mb-1">How many audio zones do you have?</label>
              <select
                id="zone_count"
                name="amp_config[zone_count]"
                phx-change="update_zone_count"
                phx-target={@myself}
                class={input_class(@errors["zone_count"])}
              >
                <option value="" selected={@form_data["zone_count"] == ""}>Select number of zones</option>
                <%= for count <- 1..16 do %>
                  <option value={to_string(count)} selected={@form_data["zone_count"] == to_string(count)}>
                    <%= count %>
                  </option>
                <% end %>
              </select>
            </div>

            <!-- Zone Names and Source Availability -->
            <%= if length(@zones) > 0 do %>
              <div class="mb-6">
                <h5 class="text-sm font-medium text-neutral-100 mb-4">Configure your zones:</h5>
                <div class="space-y-6">
                  <%= for {zone, zone_index} <- Enum.with_index(@zones) do %>
                    <div class="bg-neutral-800 rounded-lg p-4 border border-neutral-600">
                      <div class="flex items-center space-x-3 mb-4">
                        <div class="flex-1">
                          <label class="block text-sm font-medium text-neutral-300 mb-1">Zone Name</label>
                          <input
                            type="text"
                            value={zone["name"]}
                            phx-keyup="update_zone_name"
                            phx-target={@myself}
                            phx-value-index={to_string(zone_index)}
                            class={input_class(@errors["zone_#{zone_index}"])}
                            placeholder={"Zone #{zone_index + 1}"}
                          />
                          <%= if @errors["zone_#{zone_index}"] do %>
                            <p class="mt-1 text-sm text-red-400"><%= @errors["zone_#{zone_index}"] %></p>
                          <% end %>
                        </div>
                        <%= if length(@zones) > 1 do %>
                          <button
                            type="button"
                            phx-click="remove_zone"
                            phx-target={@myself}
                            phx-value-index={to_string(zone_index)}
                            class="p-2 text-red-400 hover:text-red-300 hover:bg-red-900/20 rounded-md"
                          >
                            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                            </svg>
                          </button>
                        <% end %>
                      </div>

                      <div>
                        <label class="block text-sm font-medium text-neutral-300 mb-2">Available Sources</label>
                        <div class="grid grid-cols-2 md:grid-cols-3 gap-2">
                          <%= for {source, source_index} <- Enum.with_index(@sources) do %>
                            <label class="flex items-center space-x-2 cursor-pointer">
                              <input
                                type="checkbox"
                                checked={source_index in Map.get(zone, "available_sources", [])}
                                phx-click="toggle_source_for_zone"
                                phx-target={@myself}
                                phx-value-zone_index={to_string(zone_index)}
                                phx-value-source_index={to_string(source_index)}
                                class="rounded border-neutral-600 text-blue-600 focus:ring-blue-500"
                              />
                              <span class="text-sm text-neutral-300"><%= source["name"] %></span>
                            </label>
                          <% end %>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>

                <button
                  type="button"
                  phx-click="add_zone"
                  phx-target={@myself}
                  class="mt-3 inline-flex items-center px-3 py-2 border border-neutral-600 text-sm font-medium rounded-md text-neutral-300 bg-neutral-700 hover:bg-neutral-600"
                >
                  <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                  </svg>
                  Add Zone
                </button>
              </div>
            <% end %>
          </div>
        <% end %>
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

  defp generate_sources(count) do
    Enum.map(0..(count - 1), fn index ->
      %{
        "name" => "",
        "index" => index
      }
    end)
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

  defp load_existing_config(amp_id) do
    case Devices.get_device(amp_id) do
      nil ->
        # No existing device - return empty data
        {[], [], %{"sources" => %{}, "zones" => %{}, "source_count" => "", "zone_count" => ""}}

      device ->
        # Load existing sources and zones
        sources = load_sources_from_device(device)
        zones = load_zones_from_device(device)

        form_data = %{
          "sources" => sources,
          "zones" => zones,
          "source_count" => if(length(sources) > 0, do: to_string(length(sources)), else: ""),
          "zone_count" => if(length(zones) > 0, do: to_string(length(zones)), else: "")
        }

        {sources, zones, form_data}
    end
  end

  defp load_sources_from_device(device) do
    case device.sources do
      nil -> []
      sources_map when is_map(sources_map) ->
        sources_map
        |> Map.values()
        |> Enum.sort_by(& &1["index"])
      _ -> []
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


  defp apply_source_defaults(sources) do
    sources
    |> Enum.with_index()
    |> Enum.map(fn {source, index} ->
      name =
        if String.trim(source["name"] || "") == "" do
          "Source #{index + 1}"
        else
          source["name"]
        end

      Map.put(source, "name", name)
    end)
    |> Enum.with_index()
    |> Enum.into(%{}, fn {source, index} -> {to_string(index), source} end)
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


  defp update_zones_for_sources(zones, sources) do
    source_count = length(sources)

    # Update each zone's available_sources to match the new source count
    zones
    |> Enum.map(fn zone ->
      available_sources = Map.get(zone, "available_sources", [])
      # Filter out sources that no longer exist and add new sources
      updated_sources =
        available_sources
        |> Enum.filter(&(&1 < source_count))
        |> Kernel.++(Enum.to_list(length(available_sources)..(source_count - 1)))
        |> Enum.uniq()
        |> Enum.sort()

      Map.put(zone, "available_sources", updated_sources)
    end)
  end

  defp save_sources_to_db(socket, sources) do
    # Get or create the device (default to device ID 1)
    device_id = Map.get(socket.assigns, :amp_id, 1)

    case Devices.get_device(device_id) do
      nil ->
        # Create new device with sources
        sources_with_defaults = apply_source_defaults(sources)

        Devices.create_device(%{
          name: "Amplifier",
          sources: sources_with_defaults,
          zones: %{}
        })

      device ->
        # Update existing device with sources, preserving existing zones
        sources_with_defaults = apply_source_defaults(sources)

        Devices.update_device(device, %{
          sources: sources_with_defaults
        })
    end
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
