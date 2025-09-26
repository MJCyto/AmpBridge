defmodule AmpBridgeWeb.ZoneManager do
  @moduledoc """
  Component for managing zones within an audio device.
  """

  use Phoenix.LiveComponent

  def render(assigns) do
    ~H"""
    <div class="bg-neutral-800 rounded-lg p-6 mb-6">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-xl font-semibold text-neutral-100">Zones</h3>
        <button
          phx-click="show_create_zone"
          phx-target={@myself}
          class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors"
        >
          Create Zone
        </button>
      </div>

      <%= if @show_create_zone do %>
        <div class="bg-neutral-700 rounded-lg p-4 mb-4">
          <h4 class="text-lg font-medium text-neutral-100 mb-3">Create New Zone</h4>
          <form phx-submit="create_zone" phx-target={@myself}>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-neutral-300 mb-1">Zone Name</label>
                <input
                  type="text"
                  name="zone_name"
                  required
                  class="w-full bg-neutral-600 border border-neutral-500 text-neutral-100 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                  placeholder="e.g., Bedroom, Bathroom"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-neutral-300 mb-1">Description</label>
                <input
                  type="text"
                  name="zone_description"
                  class="w-full bg-neutral-600 border border-neutral-500 text-neutral-100 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                  placeholder="Optional description"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-neutral-300 mb-1">Color</label>
                <input
                  type="color"
                  name="zone_color"
                  value="#3B82F6"
                  class="w-full bg-neutral-600 border border-neutral-500 text-neutral-100 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-neutral-300 mb-1">Initial Volume</label>
                <input
                  type="range"
                  name="zone_volume"
                  min="0"
                  max="100"
                  value="100"
                  class="w-full bg-neutral-600 border border-neutral-500 text-neutral-100 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
                <span class="text-sm text-neutral-400">100%</span>
              </div>
            </div>
            <div class="mt-4 flex gap-2">
              <button
                type="submit"
                class="bg-green-600 hover:bg-green-700 text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors"
              >
                Create Zone
              </button>
              <button
                type="button"
                phx-click="hide_create_zone"
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
        <%= for zone <- @zones do %>
          <div class="bg-neutral-700 rounded-lg p-4 border-l-4" style={"border-left-color: #{zone["color"] || "#3B82F6"}"}>
            <div class="flex items-center justify-between mb-3">
              <div>
                <h4 class="text-lg font-medium text-neutral-100"><%= zone["name"] %></h4>
                <%= if zone["description"] && zone["description"] != "" do %>
                  <p class="text-sm text-neutral-400"><%= zone["description"] %></p>
                <% end %>
              </div>
              <div class="flex items-center gap-2">
                <button
                  phx-click="toggle_zone_power"
                  phx-value-zone_id={zone["id"]}
                  phx-target={@myself}
                  class={"px-3 py-1 rounded-lg text-sm font-medium transition-colors #{if zone["power"], do: "bg-green-600 hover:bg-green-700 text-white", else: "bg-red-600 hover:bg-red-700 text-white"}"}
                >
                  <%= if zone["power"], do: "ON", else: "OFF" %>
                </button>
                <button
                  phx-click="toggle_zone_mute"
                  phx-value-zone_id={zone["id"]}
                  phx-target={@myself}
                  class={"px-3 py-1 rounded-lg text-sm font-medium transition-colors #{if zone["mute"], do: "bg-yellow-600 hover:bg-yellow-700 text-white", else: "bg-neutral-600 hover:bg-neutral-700 text-neutral-100"}"}
                >
                  <%= if zone["mute"], do: "MUTED", else: "MUTE" %>
                </button>
                <button
                  phx-click="delete_zone"
                  phx-value-zone_id={zone["id"]}
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
                    value={zone["master_volume"] || 100}
                    phx-change="update_zone_volume"
                    phx-value-zone_id={zone["id"]}
                    phx-target={@myself}
                    class="flex-1 bg-neutral-600 border border-neutral-500 text-neutral-100 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                  <span class="text-sm text-neutral-400 w-12 text-right"><%= zone["master_volume"] || 100 %>%</span>
                </div>
              </div>

              <div>
                <label class="block text-sm font-medium text-neutral-300 mb-2">Assigned Outputs</label>
                <div class="text-sm text-neutral-400">
                  <%= if length(zone["output_ids"] || []) > 0 do %>
                    <%= length(zone["output_ids"]) %> output(s) assigned
                  <% else %>
                    No outputs assigned
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        <% end %>

        <%= if length(@zones) == 0 do %>
          <div class="text-center py-8 text-neutral-400">
            <p>No zones created yet. Create your first zone to get started!</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def mount(socket) do
    {:ok, assign(socket, show_create_zone: false)}
  end

  def handle_event("show_create_zone", _, socket) do
    {:noreply, assign(socket, show_create_zone: true)}
  end

  def handle_event("hide_create_zone", _, socket) do
    {:noreply, assign(socket, show_create_zone: false)}
  end

  def handle_event(
        "create_zone",
        %{
          "zone_name" => name,
          "zone_description" => description,
          "zone_color" => color,
          "zone_volume" => volume
        },
        socket
      ) do
    zone = %{
      "id" => Ecto.UUID.generate(),
      "name" => name,
      "description" => description,
      "color" => color,
      "master_volume" => String.to_integer(volume),
      "mute" => false,
      "power" => true,
      "output_ids" => []
    }

    send(socket.assigns.parent, {:create_zone, zone})
    {:noreply, assign(socket, show_create_zone: false)}
  end

  def handle_event("update_zone_volume", %{"zone_id" => zone_id, "value" => volume}, socket) do
    send(socket.assigns.parent, {:update_zone_volume, zone_id, String.to_integer(volume)})
    {:noreply, socket}
  end

  def handle_event("toggle_zone_power", %{"zone_id" => zone_id}, socket) do
    send(socket.assigns.parent, {:toggle_zone_power, zone_id})
    {:noreply, socket}
  end

  def handle_event("toggle_zone_mute", %{"zone_id" => zone_id}, socket) do
    send(socket.assigns.parent, {:toggle_zone_mute, zone_id})
    {:noreply, socket}
  end

  def handle_event("delete_zone", %{"zone_id" => zone_id}, socket) do
    send(socket.assigns.parent, {:delete_zone, zone_id})
    {:noreply, socket}
  end
end
