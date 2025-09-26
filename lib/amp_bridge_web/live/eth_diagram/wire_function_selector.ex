defmodule AmpBridgeWeb.EthDiagramLive.WireFunctionSelector do
  use AmpBridgeWeb, :html

  def wire_function_selector(assigns) do
    IO.puts("=== RENDERING WIRE FUNCTION SELECTOR ===")
    IO.puts("Cable ID: #{assigns.cable_id}")
    IO.puts("Cable config: #{inspect(assigns.cable_config)}")

    ~H"""
    <div class="bg-neutral-500 border border-neutral-400 rounded-lg p-6 mb-6">
      <!-- Device Name Input -->
      <div class="mb-4">
        <label class="block text-sm font-medium text-neutral-300 mb-2">Device Name</label>
        <form phx-change="update_device_name" phx-value-cable-id={@cable_id}>
          <input
            type="text"
            name="device_name"
            value={get_device_name(@cable_config, @cable_id)}
            placeholder="Enter device name..."
            class="w-full px-3 py-2 bg-neutral-600 border border-neutral-400 rounded-md text-neutral-100 focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </form>
      </div>

      <!-- Wire Function Dropdowns -->
      <div class="flex flex-wrap gap-2 justify-center">
        <%= for position <- 1..8 do %>
          <form phx-change="function_changed" phx-value-position={position} phx-value-cable-id={@cable_id}>
            <select
              name="function"
              placeholder={"#{position}"}
              class="bg-neutral-600 text-neutral-200 border border-neutral-400 rounded px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 w-16"
            >
              <option value=""><%= position %></option>
              <%= for {function, available} <- get_all_functions_with_status(@cable_config, @cable_id, position) do %>
                <option
                  value={function}
                  selected={get_wire_function(@cable_config, @cable_id, position) == function}
                  disabled={!available}
                >
                  <%= function %><%= if !available, do: " (assigned)", else: "" %>
                </option>
              <% end %>
            </select>
          </form>
        <% end %>
      </div>
    </div>
    """
  end

  defp get_all_functions_with_status(cable_config, cable_id, position) do
    AmpBridge.WiringDiagramManager.get_all_functions_with_status(cable_config, cable_id, position)
  end

  defp get_wire_function(cable_config, cable_id, position) do
    cable_key = String.to_atom("cable_#{cable_id}")
    cable_data = Map.get(cable_config, cable_key, %{wires: [], device_name: ""})
    cable_array = Map.get(cable_data, :wires, [])
    wire_index = position - 1
    Enum.at(cable_array, wire_index)
  end

  defp get_device_name(cable_config, cable_id) do
    AmpBridge.WiringDiagramManager.get_device_name(cable_config, cable_id)
  end
end
