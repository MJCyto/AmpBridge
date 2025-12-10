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
    end

    # Load existing data from database
    {sources, form_data} = load_existing_sources(assigns.amp_id)

    socket =
      assign(socket,
        form_data: form_data,
        errors: %{},
        sources: sources,
        amp_id: assigns.amp_id
      )

    {:ok, socket}
  end

  def handle_info({:sources_updated, sources}, socket) do
    form_data = Map.put(socket.assigns.form_data, "sources", sources)
    {:noreply, assign(socket, sources: sources, form_data: form_data)}
  end

  @impl true
  def handle_event("form_change", %{"source_config" => form_data}, socket) do
    # Update form data and validate
    errors = validate_form(form_data)

    {:noreply, assign(socket, form_data: form_data, errors: errors)}
  end

  def handle_event("update_source_count", %{"source_config" => %{"source_count" => count}}, socket) do
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
      Phoenix.PubSub.broadcast(AmpBridge.PubSub, "source_config_updates", {:sources_updated, sources})

      {:noreply, assign(socket, form_data: form_data, sources: sources)}
    end
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
    Phoenix.PubSub.broadcast(AmpBridge.PubSub, "source_config_updates", {:sources_updated, updated_sources})

    {:noreply, assign(socket, form_data: form_data, sources: updated_sources)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <form phx-submit="form_change" phx-target={@myself}>
        <div class="space-y-6">
          <!-- Source Count Configuration -->
          <div>
            <label class="block text-sm font-medium text-neutral-300 mb-2">
              How many audio sources does your amplifier have?
            </label>
            <input
              type="number"
              name="source_config[source_count]"
              value={@form_data["source_count"]}
              phx-change="update_source_count"
              phx-blur="update_source_count"
              phx-target={@myself}
              min="1"
              max="20"
              class={input_class(@errors["source_count"])}
              placeholder="Enter number of sources (1-20)"
            />
            <%= if @errors["source_count"] do %>
              <p class="mt-1 text-sm text-red-400"><%= @errors["source_count"] %></p>
            <% end %>
          </div>

          <!-- Source Names Configuration -->
          <%= if length(@sources) > 0 do %>
            <div>
              <label class="block text-sm font-medium text-neutral-300 mb-3">
                Configure your source names:
              </label>
              <div class="space-y-3">
                <%= for {source, index} <- Enum.with_index(@sources) do %>
                  <div class="flex items-center space-x-3">
                    <label class="text-sm text-neutral-400 w-20">
                      Source <%= index + 1 %>:
                    </label>
                    <input
                      type="text"
                      name={"source_config[sources][#{index}][name]"}
                      value={source["name"]}
                      phx-blur="update_source_name"
                      phx-value-index={index}
                      phx-target={@myself}
                      class={input_class(@errors["sources_#{index}"])}
                      placeholder="Enter source name (e.g., 'CD Player', 'TV', 'Streaming')"
                    />
                  </div>
                  <%= if @errors["sources_#{index}"] do %>
                    <p class="ml-24 text-sm text-red-400"><%= @errors["sources_#{index}"] %></p>
                  <% end %>
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

  defp update_sources_count(existing_sources, new_count) do
    existing_count = length(existing_sources)

    cond do
      new_count > existing_count ->
        # Add new empty sources
        new_sources = Enum.map(existing_count..(new_count - 1), fn index ->
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
        {[], %{"sources" => %{}, "source_count" => ""}}

      device ->
        # Load existing sources
        sources = load_sources_from_device(device)

        form_data = %{
          "sources" => sources,
          "source_count" => if(length(sources) > 0, do: to_string(length(sources)), else: "")
        }

        {sources, form_data}
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
