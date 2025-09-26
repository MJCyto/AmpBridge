defmodule AmpBridgeWeb.SpeakerGroupManager do
  @moduledoc """
  Component for managing speaker groups within an audio device.
  """

  use Phoenix.LiveComponent

  def render(assigns) do
    ~H"""
    <div class="bg-neutral-800 rounded-lg p-6 mb-6">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-xl font-semibold text-neutral-100">Speaker Groups</h3>
        <button
          phx-click="show_create_speaker_group"
          phx-target={@myself}
          class="bg-green-600 hover:bg-green-700 text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors"
        >
          Create Group
        </button>
      </div>

      <%= if @show_create_speaker_group do %>
        <div class="bg-neutral-700 rounded-lg p-4 mb-4">
          <h4 class="text-lg font-medium text-neutral-100 mb-3">Create New Speaker Group</h4>
          <form phx-submit="create_speaker_group" phx-target={@myself}>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-neutral-300 mb-1">Group Name</label>
                <input
                  type="text"
                  name="group_name"
                  required
                  class="w-full bg-neutral-600 border border-neutral-500 text-neutral-100 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-green-500"
                  placeholder="e.g., Upstairs, Everywhere"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-neutral-300 mb-1">Description</label>
                <input
                  type="text"
                  name="group_description"
                  class="w-full bg-neutral-600 border border-neutral-500 text-neutral-100 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-green-500"
                  placeholder="Optional description"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-neutral-300 mb-1">Color</label>
                <input
                  type="color"
                  name="group_color"
                  value="#10B981"
                  class="w-full bg-neutral-600 border border-neutral-500 text-neutral-100 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-green-500"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-neutral-300 mb-1">Initial Volume</label>
                <input
                  type="range"
                  name="group_volume"
                  min="0"
                  max="100"
                  value="100"
                  class="w-full bg-neutral-600 border border-neutral-500 text-neutral-100 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-green-500"
                />
                <span class="text-sm text-neutral-400">100%</span>
              </div>
            </div>

            <div class="mt-4">
              <label class="block text-sm font-medium text-neutral-300 mb-2">Select Zones to Include</label>
              <div class="grid grid-cols-2 md:grid-cols-3 gap-2">
                <%= for zone <- @zones do %>
                  <label class="flex items-center space-x-2 cursor-pointer">
                    <input
                      type="checkbox"
                      name="selected_zones[]"
                      value={zone["id"]}
                      class="rounded border-neutral-500 text-green-600 focus:ring-green-500"
                    />
                    <span class="text-sm text-neutral-300"><%= zone["name"] %></span>
                  </label>
                <% end %>
              </div>
            </div>

            <div class="mt-4 flex gap-2">
              <button
                type="submit"
                class="bg-green-600 hover:bg-green-700 text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors"
              >
                Create Group
              </button>
              <button
                type="button"
                phx-click="hide_create_speaker_group"
                phx-target={@myself}
                class="bg-neutral-600 hover:bg-neutral-700 text-neutral-100 px-4 py-2 rounded-lg text-sm font-medium transition-colors"
              >
                Cancel
              </button>
            </div>
          </form>
        </div>
      <% end %>

      <div class="space-y-4">
        <%= for group <- @speaker_groups do %>
          <div class="bg-neutral-700 rounded-lg p-4 border-l-4" style={"border-left-color: #{group["color"] || "#10B981"}"}>
            <div class="flex items-center justify-between mb-3">
              <div>
                <h4 class="text-lg font-medium text-neutral-100"><%= group["name"] %></h4>
                <%= if group["description"] && group["description"] != "" do %>
                  <p class="text-sm text-neutral-400"><%= group["description"] %></p>
                <% end %>
              </div>
              <div class="flex items-center gap-2">
                <button
                  phx-click="toggle_group_power"
                  phx-value-group_id={group["id"]}
                  phx-target={@myself}
                  class={"px-3 py-1 rounded-lg text-sm font-medium transition-colors #{if group["power"], do: "bg-green-600 hover:bg-green-700 text-white", else: "bg-red-600 hover:bg-red-700 text-white"}"}
                >
                  <%= if group["power"], do: "ON", else: "OFF" %>
                </button>
                <button
                  phx-click="toggle_group_mute"
                  phx-value-group_id={group["id"]}
                  phx-target={@myself}
                  class={"px-3 py-1 rounded-lg text-sm font-medium transition-colors #{if group["mute"], do: "bg-yellow-600 hover:bg-yellow-700 text-white", else: "bg-neutral-600 hover:bg-neutral-700 text-neutral-100"}"}
                >
                  <%= if group["mute"], do: "MUTED", else: "MUTE" %>
                </button>
                <button
                  phx-click="delete_speaker_group"
                  phx-value-group_id={group["id"]}
                  phx-target={@myself}
                  class="bg-red-600 hover:bg-red-700 text-white px-3 py-1 rounded-lg text-sm font-medium transition-colors"
                >
                  Delete
                </button>
              </div>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-neutral-300 mb-2">Master Volume</label>
                <div class="flex items-center gap-3">
                  <input
                    type="range"
                    min="0"
                    max="100"
                    value={group["master_volume"] || 100}
                    phx-change="update_group_volume"
                    phx-value-group_id={group["id"]}
                    phx-target={@myself}
                    class="flex-1 bg-neutral-600 border border-neutral-500 text-neutral-100 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-green-500"
                  />
                  <span class="text-sm text-neutral-400 w-12 text-right"><%= group["master_volume"] || 100 %>%</span>
                </div>
              </div>

              <div>
                <label class="block text-sm font-medium text-neutral-300 mb-2">Included Zones</label>
                <div class="text-sm text-neutral-400">
                  <%= if length(group["zone_ids"] || []) > 0 do %>
                    <%= length(group["zone_ids"]) %> zone(s) included
                  <% else %>
                    No zones included
                  <% end %>
                </div>
              </div>
            </div>

            <%= if length(group["zone_ids"] || []) > 0 do %>
              <div class="mt-3 pt-3 border-t border-neutral-600">
                <label class="block text-sm font-medium text-neutral-300 mb-2">Zone Details</label>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-2">
                  <%= for zone_id <- group["zone_ids"] do %>
                    <%= case Enum.find(@zones, fn z -> z["id"] == zone_id end) do %>
                      <% nil -> %>
                        <span class="text-sm text-red-400">Unknown zone</span>
                      <% zone -> %>
                        <div class="text-sm text-neutral-400">
                          <span class="font-medium"><%= zone["name"] %></span>
                          <span class="text-neutral-500">(<%= zone["master_volume"] || 100 %>%)</span>
                        </div>
                    <% end %>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>

        <%= if length(@speaker_groups) == 0 do %>
          <div class="text-center py-8 text-neutral-400">
            <p>No speaker groups created yet. Create your first group to get started!</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def mount(socket) do
    {:ok, assign(socket, show_create_speaker_group: false)}
  end

  def handle_event("show_create_speaker_group", _, socket) do
    {:noreply, assign(socket, show_create_speaker_group: true)}
  end

  def handle_event("hide_create_speaker_group", _, socket) do
    {:noreply, assign(socket, show_create_speaker_group: false)}
  end

  def handle_event(
        "create_speaker_group",
        %{
          "group_name" => name,
          "group_description" => description,
          "group_color" => color,
          "group_volume" => volume,
          "selected_zones" => selected_zones
        },
        socket
      ) do
    zone_ids = if is_list(selected_zones), do: selected_zones, else: [selected_zones]

    group = %{
      "id" => Ecto.UUID.generate(),
      "name" => name,
      "description" => description,
      "color" => color,
      "master_volume" => String.to_integer(volume),
      "mute" => false,
      "power" => true,
      "zone_ids" => zone_ids
    }

    send(socket.assigns.parent, {:create_speaker_group, group})
    {:noreply, assign(socket, show_create_speaker_group: false)}
  end

  def handle_event("update_group_volume", %{"group_id" => group_id, "value" => volume}, socket) do
    send(socket.assigns.parent, {:update_group_volume, group_id, String.to_integer(volume)})
    {:noreply, socket}
  end

  def handle_event("toggle_group_power", %{"group_id" => group_id}, socket) do
    send(socket.assigns.parent, {:toggle_group_power, group_id})
    {:noreply, socket}
  end

  def handle_event("toggle_group_mute", %{"group_id" => group_id}, socket) do
    send(socket.assigns.parent, {:toggle_group_mute, group_id})
    {:noreply, socket}
  end

  def handle_event("delete_speaker_group", %{"group_id" => group_id}, socket) do
    send(socket.assigns.parent, {:delete_speaker_group, group_id})
    {:noreply, socket}
  end
end
