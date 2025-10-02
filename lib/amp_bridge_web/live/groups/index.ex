defmodule AmpBridgeWeb.GroupsLive.Index do
  use AmpBridgeWeb, :live_view
  require Logger

  alias AmpBridge.ZoneGroups
  alias AmpBridge.Devices
  import AmpBridgeWeb.PageWrapper

  @impl true
  def mount(_params, _session, socket) do
    # Load zone groups and available zones
    zone_groups = ZoneGroups.list_zone_groups(1)
    device = Devices.get_device!(1)
    available_zones = get_available_zones(device)

    {:ok, assign(socket, %{
      zone_groups: zone_groups,
      available_zones: available_zones,
      show_create_group: false,
      editing_group: nil
    })}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, uri: uri)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page_wrapper uri={@uri}>
      <div class="min-h-screen bg-neutral-900">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <!-- Header -->
          <div class="mb-8">
            <div class="flex justify-between items-center">
              <div>
                <h1 class="text-3xl font-bold text-neutral-100">Zone Groups</h1>
                <p class="mt-2 text-neutral-400">Manage groups of zones that can be controlled together</p>
              </div>
              <button
                phx-click="show_create_group"
                class="bg-blue-600 hover:bg-blue-700 text-white px-6 py-3 rounded-lg font-medium transition-colors flex items-center gap-2"
              >
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"></path>
                </svg>
                Create Group
              </button>
            </div>
          </div>

          <!-- Flash Messages -->
          <%= if Phoenix.Flash.get(@flash, :error) do %>
            <div class="bg-red-900 border border-red-600 text-red-200 px-4 py-3 rounded mb-6">
              <%= Phoenix.Flash.get(@flash, :error) %>
            </div>
          <% end %>

          <%= if Phoenix.Flash.get(@flash, :info) do %>
            <div class="bg-green-900 border border-green-600 text-green-200 px-4 py-3 rounded mb-6">
              <%= Phoenix.Flash.get(@flash, :info) %>
            </div>
          <% end %>

          <!-- Create/Edit Group Form -->
          <%= if @show_create_group do %>
            <div class="bg-neutral-800 rounded-lg p-6 mb-8">
              <div class="flex justify-between items-center mb-6">
                <h2 class="text-xl font-semibold text-neutral-200">
                  <%= if @editing_group, do: "Edit Group", else: "Create New Zone Group" %>
                </h2>
                <button
                  phx-click="hide_create_group"
                  class="text-neutral-400 hover:text-neutral-200 transition-colors"
                >
                  <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                  </svg>
                </button>
              </div>

              <form phx-submit="create_group">
                <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
                  <div>
                    <label class="block text-sm font-medium text-neutral-300 mb-2">Group Name</label>
                    <input
                      type="text"
                      name="group_name"
                      required
                      value={if @editing_group, do: @editing_group.name, else: ""}
                      class="w-full bg-neutral-700 border border-neutral-600 text-neutral-100 rounded-lg px-4 py-3 focus:outline-none focus:ring-2 focus:ring-blue-500"
                      placeholder="e.g., Main Floor"
                    />
                  </div>

                  <div>
                    <label class="block text-sm font-medium text-neutral-300 mb-2">Description</label>
                    <input
                      type="text"
                      name="group_description"
                      value={if @editing_group, do: @editing_group.description || "", else: ""}
                      class="w-full bg-neutral-700 border border-neutral-600 text-neutral-100 rounded-lg px-4 py-3 focus:outline-none focus:ring-2 focus:ring-blue-500"
                      placeholder="e.g., Living Room and Kitchen"
                    />
                  </div>
                </div>

                <!-- Zone Selection -->
                <div class="mb-6">
                  <label class="block text-sm font-medium text-neutral-300 mb-4">Select Zones</label>
                  <div class="space-y-3">
                    <%= for zone <- @available_zones do %>
                      <div class="flex items-center gap-4 p-4 bg-neutral-700 rounded-lg">
                        <input
                          type="checkbox"
                          name="selected_zones[]"
                          value={"#{zone.index}"}
                          id={"zone-#{zone.index}"}
                          class="rounded border-neutral-600 bg-neutral-800 text-blue-600 focus:ring-blue-500"
                        />
                        <label for={"zone-#{zone.index}"} class="text-neutral-200 font-medium">
                          <%= zone.name %>
                        </label>
                      </div>
                    <% end %>
                  </div>
                </div>

                <div class="flex gap-3">
                  <button
                    type="submit"
                    class="bg-green-600 hover:bg-green-700 text-white px-6 py-3 rounded-lg font-medium transition-colors flex items-center gap-2"
                  >
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
                    </svg>
                    <%= if @editing_group, do: "Update Group", else: "Create Group" %>
                  </button>
                  <button
                    type="button"
                    phx-click="hide_create_group"
                    class="bg-neutral-600 hover:bg-neutral-500 text-white px-6 py-3 rounded-lg font-medium transition-colors"
                  >
                    Cancel
                  </button>
                </div>
              </form>
            </div>
          <% end %>

          <!-- Groups List -->
          <div class="space-y-6">
            <%= if length(@zone_groups) > 0 do %>
              <%= for group <- @zone_groups do %>
                <div class="bg-neutral-800 rounded-lg p-6">
                  <div class="flex justify-between items-start mb-4">
                    <div class="flex-1">
                      <h3 class="text-xl font-semibold text-neutral-200 mb-2"><%= group.name %></h3>
                      <%= if group.description && group.description != "" do %>
                        <p class="text-neutral-400 mb-3"><%= group.description %></p>
                      <% end %>
                      <div class="flex items-center gap-4 text-sm text-neutral-500">
                        <span><%= length(group.zone_group_memberships) %> zones</span>
                        <span>•</span>
                        <span>Created <%= Calendar.strftime(group.inserted_at, "%B %d, %Y") %></span>
                      </div>
                    </div>
                    <div class="flex gap-2">
                      <button
                        phx-click="edit_group"
                        phx-value-group_id={group.id}
                        class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg text-sm transition-colors flex items-center gap-2"
                      >
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"></path>
                        </svg>
                        Edit
                      </button>
                      <button
                        phx-click="delete_group"
                        phx-value-group_id={group.id}
                        class="bg-red-600 hover:bg-red-700 text-white px-4 py-2 rounded-lg text-sm transition-colors flex items-center gap-2"
                      >
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
                        </svg>
                        Delete
                      </button>
                    </div>
                  </div>

                  <!-- Zone Details -->
                  <div class="border-t border-neutral-700 pt-4">
                    <h4 class="text-sm font-medium text-neutral-300 mb-3">Zones in Group</h4>
                    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
                      <%= for membership <- group.zone_group_memberships do %>
                        <div class="bg-neutral-700 rounded-lg p-3">
                          <div class="flex justify-between items-center">
                            <span class="text-neutral-200 font-medium">Zone <%= membership.zone_index + 1 %></span>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% end %>
            <% else %>
              <div class="text-center py-12">
                <svg class="mx-auto h-12 w-12 text-neutral-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"></path>
                </svg>
                <h3 class="mt-4 text-lg font-medium text-neutral-200">No zone groups</h3>
                <p class="mt-2 text-neutral-400">Get started by creating your first zone group.</p>
                <div class="mt-6">
                  <button
                    phx-click="show_create_group"
                    class="bg-blue-600 hover:bg-blue-700 text-white px-6 py-3 rounded-lg font-medium transition-colors inline-flex items-center gap-2"
                  >
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"></path>
                    </svg>
                    Create Group
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>

    </.page_wrapper>
    """
  end

  @impl true
  def handle_event("show_create_group", _, socket) do
    {:noreply, assign(socket, show_create_group: true)}
  end

  @impl true
  def handle_event("hide_create_group", _, socket) do
    {:noreply, assign(socket, show_create_group: false)}
  end

  @impl true
  def handle_event("create_group", params, socket) do
    Logger.info("Create group params: #{inspect(params)}")

    name = Map.get(params, "group_name", "")
    description = Map.get(params, "group_description", "")
    selected_zones = Map.get(params, "selected_zones", [])

    Logger.info("Selected zones: #{inspect(selected_zones)}")

    # Validate that at least one zone is selected
    if length(selected_zones) == 0 do
      Logger.warning("No zones selected for group creation")
      {:noreply, put_flash(socket, :error, "Please select at least one zone for the group.")}
    else
      # Parse selected zones (format: "zone_index:volume_modifier:order_index")
      zone_memberships = parse_selected_zones(selected_zones)
      Logger.info("Parsed zone memberships: #{inspect(zone_memberships)}")

      group_attrs = %{
        name: name,
        description: description,
        audio_device_id: 1,
        is_active: true
      }

      case ZoneGroups.create_zone_group_with_zones(group_attrs, zone_memberships) do
        {:ok, _zone_group} ->
          Logger.info("Created zone group: #{name}")
          # Refresh the groups list
          zone_groups = ZoneGroups.list_zone_groups(1)
          {:noreply, assign(socket, zone_groups: zone_groups, show_create_group: false) |> put_flash(:info, "Group '#{name}' created successfully!")}

        {:error, changeset} ->
          Logger.error("Failed to create zone group: #{inspect(changeset)}")
          {:noreply, put_flash(socket, :error, "Failed to create group: #{inspect(changeset.errors)}")}
      end
    end
  end

  @impl true
  def handle_event("delete_group", %{"group_id" => group_id}, socket) do
    group_id_int = String.to_integer(group_id)

    case ZoneGroups.get_zone_group(group_id_int) do
      nil ->
        {:noreply, put_flash(socket, :error, "Group not found")}

      zone_group ->
        case ZoneGroups.delete_zone_group(zone_group) do
          {:ok, _} ->
            Logger.info("Deleted zone group: #{zone_group.name}")
            # Refresh the groups list
            zone_groups = ZoneGroups.list_zone_groups(1)
            {:noreply, assign(socket, zone_groups: zone_groups)}

          {:error, changeset} ->
            Logger.error("Failed to delete zone group: #{inspect(changeset)}")
            {:noreply, put_flash(socket, :error, "Failed to delete group: #{inspect(changeset.errors)}")}
        end
    end
  end

  @impl true
  def handle_event("edit_group", %{"group_id" => group_id}, socket) do
    group_id_int = String.to_integer(group_id)

    case ZoneGroups.get_zone_group(group_id_int) do
      nil ->
        {:noreply, put_flash(socket, :error, "Group not found")}

      group ->
        {:noreply, assign(socket, editing_group: group, show_create_group: true)}
    end
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
    Enum.map(selected_zones, fn zone_index_str ->
      %{
        zone_index: String.to_integer(zone_index_str)
      }
    end)
  end

  defp parse_selected_zones(_), do: []
end
