defmodule AmpBridgeWeb.SourceConfigComponent do
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
      Phoenix.PubSub.subscribe(AmpBridge.PubSub, "source_config_updates")
      Phoenix.PubSub.subscribe(AmpBridge.PubSub, "zone_config_updates")
    end

    # Load existing data from database
    {sources, zones, form_data} = load_existing_sources(assigns.amp_id)

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
    form_data = Map.put(socket.assigns.form_data, "sources", sources)
    {:noreply, assign(socket, sources: sources, form_data: form_data)}
  end

  def handle_info({:zones_updated, zones}, socket) do
    {:noreply, assign(socket, zones: zones)}
  end

  @impl true
  def handle_event("form_change", %{"source_config" => form_data}, socket) do
    # Update form data and validate
    errors = validate_form(form_data)

    {:noreply, assign(socket, form_data: form_data, errors: errors)}
  end

  def handle_event(
        "update_source_count",
        %{"source_config" => %{"source_count" => count}},
        socket
      ) do
    if count == "" do
      form_data = Map.put(socket.assigns.form_data, "source_count", "")
      # Broadcast the change
      Phoenix.PubSub.broadcast(AmpBridge.PubSub, "source_config_updates", {:sources_updated, []})
      {:noreply, assign(socket, form_data: form_data, sources: [])}
    else
      count_int = String.to_integer(count)
      existing_sources = socket.assigns.sources

      # Preserve existing sources and add new ones if count increased
      sources = update_sources_count(existing_sources, count_int)

      form_data = Map.put(socket.assigns.form_data, "source_count", count)
      form_data = Map.put(form_data, "sources", sources)

      # Save to database and broadcast
      save_sources_to_db(socket, sources)

      Phoenix.PubSub.broadcast(
        AmpBridge.PubSub,
        "source_config_updates",
        {:sources_updated, sources}
      )

      {:noreply, assign(socket, form_data: form_data, sources: sources)}
    end
  end

  def handle_event("add_source", _params, socket) do
    sources = update_sources_count(socket.assigns.sources, length(socket.assigns.sources) + 1)
    persist_sources(socket, sources)
  end

  def handle_event("delete_source", %{"index" => index}, socket) do
    source_index = String.to_integer(index)

    sources =
      socket.assigns.sources
      |> List.delete_at(source_index)
      |> Enum.with_index()
      |> Enum.map(fn {source, new_index} -> Map.put(source, "index", new_index) end)

    zones = reindex_zone_sources(socket.assigns.zones, source_index)
    persist_sources(socket, sources, zones)
  end

  def handle_event("update_source_name", %{"index" => index, "value" => name}, socket) do
    index_int = String.to_integer(index)
    sources = socket.assigns.sources

    updated_sources =
      sources
      |> Enum.with_index()
      |> Enum.map(fn {source, i} ->
        if i == index_int do
          Map.put(source, "name", name)
        else
          source
        end
      end)

    form_data = Map.put(socket.assigns.form_data, "sources", updated_sources)

    # Save to database and broadcast
    save_sources_to_db(socket, updated_sources)

    Phoenix.PubSub.broadcast(
      AmpBridge.PubSub,
      "source_config_updates",
      {:sources_updated, updated_sources}
    )

    {:noreply, assign(socket, form_data: form_data, sources: updated_sources)}
  end

  def handle_event(
        "update_source_zones",
        %{"index" => index} = params,
        socket
      ) do
    source_index = String.to_integer(index)

    selected_zone_indices =
      params
      |> Map.get("zones", [])
      |> List.wrap()
      |> Enum.map(&String.to_integer/1)

    zones =
      update_zone_source_membership(socket.assigns.zones, source_index, selected_zone_indices)

    save_zones_to_db(socket, zones)
    Phoenix.PubSub.broadcast(AmpBridge.PubSub, "zone_config_updates", {:zones_updated, zones})
    {:noreply, assign(socket, zones: zones)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <form phx-submit="form_change" phx-target={@myself}>
        <div class="space-y-6">
          <div class="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
                <%= for {source, index} <- Enum.with_index(@sources) do %>
                  <div x-data="{confirming: false, open: false}" class="rounded-lg bg-neutral-800 p-4">
                    <div class="flex items-center gap-3">
                    <input
                      type="text"
                      name={"source_config[sources][#{index}][name]"}
                      value={source["name"]}
                      phx-blur="update_source_name"
                      phx-value-index={index}
                      phx-target={@myself}
                      class={input_class(@errors["sources_#{index}"]) <> " flex-1"}
                      placeholder={"Source #{index + 1} name"}
                    />
                    <button type="button" @click="confirming = true" class="text-red-400 hover:text-red-300" aria-label={"Delete source #{index + 1}"} title="Delete source">
                      <.icon url="/images/trash.svg" class="h-5 w-5" />
                    </button>
                    </div>
                    <%= if @errors["sources_#{index}"] do %>
                      <p class="mt-2 text-sm text-red-400"><%= @errors["sources_#{index}"] %></p>
                    <% end %>
                    <%= if length(@zones) > 0 do %>
                      <div class="relative mt-4" @click.outside="open = false">
                        <button type="button" @click="open = !open" class="flex w-full items-center justify-between rounded-md border border-neutral-600 bg-neutral-800 px-3 py-2 text-left text-sm text-neutral-300">
                          <span>Zones (<%= source_zone_count(@zones, index) %>)</span><span aria-hidden="true">▾</span>
                        </button>
                        <div x-show="open" x-cloak class="absolute z-10 mt-1 w-full rounded-md border border-neutral-600 bg-neutral-800 p-3 shadow-lg">
                          <div class="space-y-2">
                            <%= for {zone, zone_index} <- Enum.with_index(@zones) do %>
                              <label class="flex items-center space-x-2">
                                <input type="checkbox" name={"source_config[sources][#{index}][zones][]"} value={zone_index} checked={source_index_in_zone?(zone, index)} phx-change="update_source_zones" phx-value-index={index} phx-target={@myself} class="rounded border-neutral-600 bg-neutral-700 text-blue-600 focus:ring-blue-500" />
                                <span class="text-sm text-neutral-300"><%= zone["name"] || "Zone #{zone_index + 1}" %></span>
                              </label>
                            <% end %>
                          </div>
                        </div>
                      </div>
                    <% end %>
                    <div x-show="confirming" x-cloak class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4" role="dialog" aria-modal="true" @click="confirming = false">
                      <div class="w-full max-w-sm rounded-lg border border-neutral-600 bg-neutral-800 p-5 shadow-xl" @click.stop>
                        <h2 class="text-lg font-semibold text-neutral-100">Delete source?</h2>
                        <p class="mt-2 text-sm text-neutral-400">This action cannot be reverted.</p>
                        <div class="mt-5 flex justify-end gap-3"><button type="button" @click="confirming = false" class="rounded-md border border-neutral-600 px-3 py-2 text-sm text-neutral-300">Cancel</button><button type="button" phx-click="delete_source" phx-value-index={index} phx-target={@myself} @click="confirming = false" class="rounded-md bg-red-600 px-3 py-2 text-sm font-medium text-white">Delete source</button></div>
                      </div>
                    </div>
                  </div>
                <% end %>
                <button type="button" phx-click="add_source" phx-target={@myself} class="min-h-32 rounded-lg border-2 border-dashed border-neutral-600 text-neutral-400 hover:border-blue-500 hover:text-blue-400"><span class="text-3xl leading-none">+</span><span class="mt-2 block text-sm">Add source</span></button>
          </div>
        </div>
      </form>
    </div>
    """
  end

  defp input_class(error) do
    base_class =
      "w-full px-3 py-2 bg-neutral-800 text-neutral-100 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"

    if error do
      base_class <> " border-red-500"
    else
      base_class <> " border-neutral-600"
    end
  end

  defp update_sources_count(existing_sources, new_count) do
    existing_count = length(existing_sources)

    cond do
      new_count > existing_count ->
        # Add new empty sources
        new_sources =
          Enum.map(existing_count..(new_count - 1), fn index ->
            %{
              "name" => "",
              "index" => index
            }
          end)

        existing_sources ++ new_sources

      new_count < existing_count ->
        # Remove extra sources (keep first new_count sources)
        existing_sources
        |> Enum.take(new_count)
        |> Enum.with_index()
        |> Enum.map(fn {source, index} ->
          Map.put(source, "index", index)
        end)

      true ->
        # Count unchanged, return existing sources
        existing_sources
    end
  end

  defp validate_form(_form_data) do
    %{}
  end

  defp load_existing_sources(amp_id) do
    case Devices.get_device(amp_id) do
      nil ->
        # No existing device - return empty data
        {[], [], %{"sources" => %{}, "source_count" => ""}}

      device ->
        # Load existing sources
        sources = load_sources_from_device(device)

        form_data = %{
          "sources" => sources,
          "source_count" => if(length(sources) > 0, do: to_string(length(sources)), else: "")
        }

        {sources, load_zones_from_device(device), form_data}
    end
  end

  defp load_sources_from_device(device) do
    case device.sources do
      nil ->
        []

      sources_map when is_map(sources_map) ->
        sources_map
        |> Map.values()
        |> Enum.sort_by(& &1["index"])

      _ ->
        []
    end
  end

  defp load_zones_from_device(device) do
    case device.zones do
      zones when is_map(zones) ->
        zones |> Map.values() |> Enum.sort_by(& &1["index"])

      _ ->
        []
    end
  end

  defp source_index_in_zone?(zone, source_index),
    do: source_index in Map.get(zone, "available_sources", [])

  defp source_zone_count(zones, source_index),
    do: Enum.count(zones, &source_index_in_zone?(&1, source_index))

  defp update_zone_source_membership(zones, source_index, selected_zone_indices) do
    zones
    |> Enum.with_index()
    |> Enum.map(fn {zone, zone_index} ->
      available = Map.get(zone, "available_sources", [])

      updated =
        if zone_index in selected_zone_indices,
          do: Enum.uniq([source_index | available]),
          else: List.delete(available, source_index)

      Map.put(zone, "available_sources", Enum.sort(updated))
    end)
    |> zones_to_map()
  end

  defp reindex_zone_sources(zones, removed_source_index) do
    zones
    |> Enum.map(fn zone ->
      available =
        zone
        |> Map.get("available_sources", [])
        |> Enum.reject(&(&1 == removed_source_index))
        |> Enum.map(fn index -> if index > removed_source_index, do: index - 1, else: index end)

      Map.put(zone, "available_sources", available)
    end)
    |> zones_to_map()
  end

  defp zones_to_map(zones),
    do:
      zones
      |> Enum.with_index()
      |> Enum.into(%{}, fn {zone, index} -> {to_string(index), Map.put(zone, "index", index)} end)

  defp persist_sources(socket, sources, zones \\ nil) do
    zones = zones || socket.assigns.zones
    save_sources_to_db(socket, sources)
    save_zones_to_db(socket, zones)

    Phoenix.PubSub.broadcast(
      AmpBridge.PubSub,
      "source_config_updates",
      {:sources_updated, sources}
    )

    Phoenix.PubSub.broadcast(AmpBridge.PubSub, "zone_config_updates", {:zones_updated, zones})

    form_data =
      socket.assigns.form_data
      |> Map.put("source_count", to_string(length(sources)))
      |> Map.put("sources", sources)

    {:noreply, assign(socket, sources: sources, zones: zones, form_data: form_data)}
  end

  defp save_zones_to_db(socket, zones) do
    case Devices.get_device(socket.assigns.amp_id) do
      nil -> :ok
      device -> Devices.update_device(device, %{zones: zones})
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

  defp save_sources_to_db(socket, sources) do
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
end
