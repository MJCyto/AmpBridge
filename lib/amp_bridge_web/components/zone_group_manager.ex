defmodule AmpBridgeWeb.ZoneGroupManager do
  use Phoenix.LiveComponent
  require Logger

  alias AmpBridge.ZoneGroups
  alias AmpBridge.Devices

  attr(:audio_device_id, :integer, required: true, doc: "Audio device ID")
  attr(:myself, :any, default: nil, doc: "Component ID for phx-target")

  @impl true
  def mount(socket) do
    {:ok, assign(socket, show_create_group: false)}
  end

  @impl true
  def update(assigns, socket) do
    # Load zone groups and available zones
    zone_groups = ZoneGroups.list_zone_groups(assigns.audio_device_id)
    device = Devices.get_device!(assigns.audio_device_id)
    available_zones = get_available_zones(device)

    {:ok, assign(socket, Map.merge(assigns, %{
      zone_groups: zone_groups,
      available_zones: available_zones
    }))}
  end

  @impl true
  def handle_event("show_create_group", _, socket) do
    {:noreply, assign(socket, show_create_group: true)}
  end

  def handle_event("hide_create_group", _, socket) do
    {:noreply, assign(socket, show_create_group: false)}
  end

  def handle_event("create_group", %{
        "group_name" => name,
        "group_description" => description,
        "selected_zones" => selected_zones
      }, socket) do
    # Parse selected zones (format: "zone_index:volume_modifier:order_index")
    zone_memberships = parse_selected_zones(selected_zones)

    group_attrs = %{
      name: name,
      description: description,
      audio_device_id: socket.assigns.audio_device_id,
      is_active: true
    }

    case ZoneGroups.create_zone_group_with_zones(group_attrs, zone_memberships) do
      {:ok, _zone_group} ->
        Logger.info("Created zone group: #{name}")
        # Refresh the groups list
        zone_groups = ZoneGroups.list_zone_groups(socket.assigns.audio_device_id)
        {:noreply, assign(socket, zone_groups: zone_groups, show_create_group: false)}

      {:error, changeset} ->
        Logger.error("Failed to create zone group: #{inspect(changeset)}")
        {:noreply, socket}
    end
  end

  def handle_event("delete_group", %{"group_id" => group_id}, socket) do
    group_id_int = String.to_integer(group_id)

    case ZoneGroups.get_zone_group(group_id_int) do
      nil ->
        {:noreply, socket}

      zone_group ->
        case ZoneGroups.delete_zone_group(zone_group) do
          {:ok, _} ->
            Logger.info("Deleted zone group: #{zone_group.name}")
            # Refresh the groups list
            zone_groups = ZoneGroups.list_zone_groups(socket.assigns.audio_device_id)
            {:noreply, assign(socket, zone_groups: zone_groups)}

          {:error, changeset} ->
            Logger.error("Failed to delete zone group: #{inspect(changeset)}")
            {:noreply, socket}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-neutral-700 rounded-lg p-6">
      <div class="flex justify-between items-center mb-6">
        <h3 class="text-xl font-semibold text-neutral-200">Zone Groups</h3>
        <button
          phx-click="show_create_group"
          phx-target={@myself}
          class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg transition-colors"
        >
          Create Group
        </button>
      </div>

      <!-- Create Group Form -->
      <%= if @show_create_group do %>
        <div class="bg-neutral-800 rounded-lg p-4 mb-6">
          <h4 class="text-lg font-semibold text-neutral-200 mb-4">Create New Zone Group</h4>

          <form phx-submit="create_group" phx-target={@myself}>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
              <div>
                <label class="block text-sm font-medium text-neutral-300 mb-2">Group Name</label>
                <input
                  type="text"
                  name="group_name"
                  required
                  class="w-full bg-neutral-600 border border-neutral-500 text-neutral-100 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                  placeholder="e.g., Main Floor"
                />
              </div>

              <div>
                <label class="block text-sm font-medium text-neutral-300 mb-2">Description</label>
                <input
                  type="text"
                  name="group_description"
                  class="w-full bg-neutral-600 border border-neutral-500 text-neutral-100 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                  placeholder="e.g., Living Room and Kitchen"
                />
              </div>
            </div>

            <!-- Zone Selection -->
            <div class="mb-4">
              <label class="block text-sm font-medium text-neutral-300 mb-2">Select Zones</label>
              <div class="space-y-2">
                <%= for zone <- @available_zones do %>
                  <div class="flex items-center gap-4 p-2 bg-neutral-700 rounded">
                    <input
                      type="checkbox"
                      name="selected_zones[]"
                      value={"#{zone.index}:1.0:#{zone.index}"}
                      id={"zone-#{zone.index}"}
                      class="rounded"
                    />
                    <label for={"zone-#{zone.index}"} class="text-neutral-200">
                      <%= zone.name %>
                    </label>
                    <div class="ml-auto flex items-center gap-2">
                      <label class="text-sm text-neutral-400">Volume Modifier:</label>
                      <input
                        type="number"
                        min="0.1"
                        max="2.0"
                        step="0.1"
                        value="1.0"
                        class="w-16 bg-neutral-600 border border-neutral-500 text-neutral-100 rounded px-2 py-1 text-sm"
                        onchange={"updateZoneModifier(#{zone.index}, this.value)"}
                      />
                      <label class="text-sm text-neutral-400">Order:</label>
                      <input
                        type="number"
                        min="0"
                        value={zone.index}
                        class="w-16 bg-neutral-600 border border-neutral-500 text-neutral-100 rounded px-2 py-1 text-sm"
                        onchange={"updateZoneOrder(#{zone.index}, this.value)"}
                      />
                    </div>
                  </div>
                <% end %>
              </div>
            </div>

            <div class="flex gap-2">
              <button
                type="submit"
                class="bg-green-600 hover:bg-green-700 text-white px-4 py-2 rounded-lg transition-colors"
              >
                Create Group
              </button>
              <button
                type="button"
                phx-click="hide_create_group"
                phx-target={@myself}
                class="bg-neutral-600 hover:bg-neutral-500 text-white px-4 py-2 rounded-lg transition-colors"
              >
                Cancel
              </button>
            </div>
          </form>
        </div>
      <% end %>

      <!-- Zone Groups List -->
      <div class="space-y-4">
        <%= if length(@zone_groups) > 0 do %>
          <%= for group <- @zone_groups do %>
            <div class="bg-neutral-800 rounded-lg p-4">
              <div class="flex justify-between items-start mb-2">
                <div>
                  <h4 class="text-lg font-semibold text-neutral-200"><%= group.name %></h4>
                  <%= if group.description do %>
                    <p class="text-sm text-neutral-400"><%= group.description %></p>
                  <% end %>
                </div>
                <button
                  phx-click="delete_group"
                  phx-value-group_id={group.id}
                  phx-target={@myself}
                  class="bg-red-600 hover:bg-red-700 text-white px-3 py-1 rounded text-sm transition-colors"
                >
                  Delete
                </button>
              </div>

              <div class="text-sm text-neutral-400">
                <%= length(group.zone_group_memberships) %> zones configured
              </div>
            </div>
          <% end %>
        <% else %>
          <div class="text-center py-8 text-neutral-400">
            <p>No zone groups created yet. Create your first group to get started!</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Private helper functions

  defp get_available_zones(device) do
    if device && device.zones && map_size(device.zones) > 0 do
      device.zones
      |> Map.keys()
      |> Enum.map(&String.to_integer/1)
      |> Enum.filter(fn zone -> zone >= 0 end)
      |> Enum.sort()
      |> Enum.map(fn zone_index ->
        zone_name = get_zone_name(device, zone_index)
        %{
          index: zone_index,
          name: zone_name || "Zone #{zone_index + 1}"
        }
      end)
    else
      []
    end
  end

  defp get_zone_name(device_config, zone) do
    if device_config && device_config.zones do
      case Map.get(device_config.zones, to_string(zone)) do
        %{"name" => name} when is_binary(name) and name != "" -> name
        _ -> nil
      end
    else
      nil
    end
  end

  defp parse_selected_zones(selected_zones) when is_list(selected_zones) do
    Enum.map(selected_zones, fn zone_string ->
      [zone_index_str, volume_modifier_str, order_index_str] = String.split(zone_string, ":")

      %{
        zone_index: String.to_integer(zone_index_str),
        volume_modifier: String.to_float(volume_modifier_str),
        order_index: String.to_integer(order_index_str)
      }
    end)
  end

  defp parse_selected_zones(_), do: []
end
