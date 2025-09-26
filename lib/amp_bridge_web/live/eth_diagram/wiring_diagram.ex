defmodule AmpBridgeWeb.EthDiagramLive.WiringDiagram do
  use AmpBridgeWeb, :live_component
  import AmpBridgeWeb.EthDiagramLive.WireFunctionSelector

  def render(assigns) do
    ~H"""
    <div class="bg-neutral-600 rounded-lg p-6">
      <div class="flex justify-center gap-4 mb-8">
        <button
          phx-click="reset_to_standard"
          class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors"
        >
          Standard (T568B)
        </button>
        <button
          phx-click="reset_to_crossover"
          class="px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 transition-colors"
        >
          Crossover
        </button>
        <button
          phx-click="clear_connections"
          class="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700 transition-colors"
        >
          Clear All
        </button>
      </div>

      <!-- Wire Function Selector Components -->
      <div class="mb-6">
        <h3 class="text-lg font-semibold text-neutral-200 mb-4 text-center">Cable 1 (Left End)</h3>
        <.wire_function_selector
          cable_config={@cable_config}
          cable_id={1}
        />
      </div>

      <div class="mb-6">
        <h3 class="text-lg font-semibold text-neutral-200 mb-4 text-center">Cable 2 (Right End)</h3>
        <.wire_function_selector
          cable_config={@cable_config}
          cable_id={2}
        />
      </div>

      <!-- Wire Order Summary -->
      <div class="bg-neutral-500 border border-neutral-400 rounded-lg p-6">
        <h3 class="text-lg font-semibold text-neutral-200 mb-4 text-center">Wire Order (Left to Right)</h3>

        <!-- Cable 1 Row -->
        <div class="mb-6">
          <div class="text-center text-neutral-200 font-medium mb-3">
            <%= get_device_name(@cable_config, 1) %>
          </div>
          <div class="flex gap-3 justify-center">
            <%= for position <- 1..8 do %>
              <% wire_color = AmpBridge.WiringDiagramManager.get_tia_b_wire_color(position) %>
              <% signal = get_wire_function(@cable_config, 1, position) %>
              <% has_signal = signal != "" and signal != nil %>
              <div class="flex flex-col items-center gap-2">
                <div class={get_wire_class_with_transparency(wire_color, has_signal)}></div>
                <span class="text-xs text-neutral-300 text-center">
                  <%= if signal == "" or signal == nil, do: position, else: signal %>
                </span>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Cable 2 Row -->
        <div>
          <div class="text-center text-neutral-200 font-medium mb-3">
            <%= get_device_name(@cable_config, 2) %>
          </div>
          <div class="flex gap-3 justify-center">
            <%= for position <- 1..8 do %>
              <% wire_color = get_connected_wire_color(@cable_config, position) %>
              <% signal = get_wire_function(@cable_config, 2, position) %>
              <div class="flex flex-col items-center gap-2">
                <div class={get_wire_class(wire_color)}></div>
                <span class="text-xs text-neutral-300 text-center">
                  <%= if signal == "" or signal == nil, do: position, else: signal %>
                </span>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("reset_to_standard", _params, socket) do
    # Reset to TIA B standard with proper signal swapping
    wiring_config = AmpBridge.WiringDiagramManager.generate_wiring_diagram()

    # Generate connections based on the wiring config
    standard_connections =
      socket.assigns.wire_colors
      |> Enum.with_index(1)
      |> Enum.map(fn {wire, position} -> {wire.id, %{end: :right, position: position}} end)
      |> Map.new()

    {:noreply, assign(socket, connections: standard_connections, cable_config: wiring_config)}
  end

  def handle_event("reset_to_crossover", _params, socket) do
    # Reset to crossover configuration
    crossover_connections = %{
      # white-orange -> white-green
      1 => %{end: :right, position: 3},
      # orange -> green
      2 => %{end: :right, position: 6},
      # white-green -> white-orange
      3 => %{end: :right, position: 1},
      # blue -> blue
      4 => %{end: :right, position: 4},
      # white-blue -> white-blue
      5 => %{end: :right, position: 5},
      # green -> orange
      6 => %{end: :right, position: 2},
      # white-brown -> white-brown
      7 => %{end: :right, position: 7},
      # brown -> brown
      8 => %{end: :right, position: 8}
    }

    {:noreply, assign(socket, connections: crossover_connections)}
  end

  def handle_event("clear_connections", _params, socket) do
    {:noreply, assign(socket, connections: %{})}
  end

  defp get_wire_class(color) do
    base_classes = "w-5 h-10 rounded shadow-sm"

    case color do
      "white-orange" ->
        get_striped_wire_class(base_classes, "orange")

      "orange" ->
        "#{base_classes} bg-orange-500"

      "white-green" ->
        get_striped_wire_class(base_classes, "green")

      "blue" ->
        "#{base_classes} bg-blue-500"

      "white-blue" ->
        get_striped_wire_class(base_classes, "blue")

      "green" ->
        "#{base_classes} bg-green-500"

      "white-brown" ->
        get_striped_wire_class(base_classes, "amber-700")

      "brown" ->
        "#{base_classes} bg-amber-700"

      "grey" ->
        "#{base_classes} bg-neutral-800"

      _ ->
        "#{base_classes} bg-neutral-500"
    end
  end

  defp get_wire_class_with_transparency(color, has_signal) do
    base_classes = "w-5 h-10 rounded shadow-sm"
    opacity_class = if has_signal, do: "", else: " opacity-50"

    case color do
      "white-orange" ->
        get_striped_wire_class_with_transparency(base_classes, "orange", has_signal)

      "orange" ->
        "#{base_classes} bg-orange-500#{opacity_class}"

      "white-green" ->
        get_striped_wire_class_with_transparency(base_classes, "green", has_signal)

      "blue" ->
        "#{base_classes} bg-blue-500#{opacity_class}"

      "white-blue" ->
        get_striped_wire_class_with_transparency(base_classes, "blue", has_signal)

      "green" ->
        "#{base_classes} bg-green-500#{opacity_class}"

      "white-brown" ->
        get_striped_wire_class_with_transparency(base_classes, "amber-700", has_signal)

      "brown" ->
        "#{base_classes} bg-amber-700#{opacity_class}"

      "grey" ->
        "#{base_classes} bg-neutral-800#{opacity_class}"

      _ ->
        "#{base_classes} bg-neutral-500#{opacity_class}"
    end
  end

  defp get_striped_wire_class(base_classes, color) do
    case color do
      "orange" ->
        "#{base_classes} bg-[repeating-linear-gradient(65deg,white,white_0.5rem,#f97316_0.5rem,#f97316_1rem)]"

      "green" ->
        "#{base_classes} bg-[repeating-linear-gradient(65deg,white,white_0.5rem,#22c55e_0.5rem,#22c55e_1rem)]"

      "blue" ->
        "#{base_classes} bg-[repeating-linear-gradient(65deg,white,white_0.5rem,#3b82f6_0.5rem,#3b82f6_1rem)]"

      "amber-700" ->
        "#{base_classes} bg-[repeating-linear-gradient(65deg,white,white_0.5rem,#b45309_0.5rem,#b45309_1rem)]"

      _ ->
        "#{base_classes} bg-neutral-500"
    end
  end

  defp get_striped_wire_class_with_transparency(base_classes, color, has_signal) do
    opacity_class = if has_signal, do: "", else: " opacity-50"

    case color do
      "orange" ->
        "#{base_classes} bg-[repeating-linear-gradient(65deg,white,white_0.5rem,#f97316_0.5rem,#f97316_1rem)]#{opacity_class}"

      "green" ->
        "#{base_classes} bg-[repeating-linear-gradient(65deg,white,white_0.5rem,#22c55e_0.5rem,#22c55e_1rem)]#{opacity_class}"

      "blue" ->
        "#{base_classes} bg-[repeating-linear-gradient(65deg,white,white_0.5rem,#3b82f6_0.5rem,#3b82f6_1rem)]#{opacity_class}"

      "amber-700" ->
        "#{base_classes} bg-[repeating-linear-gradient(65deg,white,white_0.5rem,#b45309_0.5rem,#b45309_1rem)]#{opacity_class}"

      _ ->
        "#{base_classes} bg-neutral-500#{opacity_class}"
    end
  end

  defp get_wire_function(cable_config, cable_id, position) do
    cable_key = String.to_atom("cable_#{cable_id}")
    cable_data = Map.get(cable_config, cable_key, %{wires: [], device_name: ""})
    cable_array = Map.get(cable_data, :wires, [])
    wire_index = position - 1
    Enum.at(cable_array, wire_index) || ""
  end

  defp get_device_name(cable_config, cable_id) do
    cable_key = String.to_atom("cable_#{cable_id}")
    cable_data = Map.get(cable_config, cable_key, %{wires: [], device_name: ""})
    device_name = Map.get(cable_data, :device_name, "")
    if device_name == "" or device_name == nil, do: "Device #{cable_id}", else: device_name
  end

  defp get_connected_wire_color(cable_config, device2_position) do
    # Get the signal assigned to Device 2 at this position
    device2_signal = get_wire_function(cable_config, 2, device2_position)

    # If no signal assigned to Device 2, show grey wire
    if device2_signal == "" or device2_signal == nil do
      "grey"
    else
      # Map Device 2 signal to Device 1 signal
      device1_signal = map_device2_to_device1_signal(device2_signal)

      # Find which Device 1 position has that signal
      device1_position = find_device1_position_with_signal(cable_config, device1_signal)

      if device1_position do
        # Return the TIA B color for the Device 1 position
        AmpBridge.WiringDiagramManager.get_tia_b_wire_color(device1_position)
      else
        # If no matching signal found, show grey wire
        "grey"
      end
    end
  end

  defp map_device2_to_device1_signal(device2_signal) do
    # Simple mapping: Device 2 signal -> Device 1 signal
    # Only swap data flow signals (TX/RX) and handshaking signals (RTS/CTS)
    # Status signals (DCD, DSR, DTR) and GND are not swapped
    case device2_signal do
      "RX+" -> "TX+"
      "RX-" -> "TX-"
      "TX+" -> "RX+"
      "TX-" -> "RX-"
      "RX" -> "TX"
      "TX" -> "RX"
      "RTS" -> "CTS"
      "CTS" -> "RTS"
      # For exact matches (GND, DTR, DSR, DCD, NC) - these are not swapped
      signal -> signal
    end
  end

  defp find_device1_position_with_signal(cable_config, signal) do
    for position <- 1..8 do
      device1_signal = get_wire_function(cable_config, 1, position)
      if device1_signal == signal, do: position, else: nil
    end
    |> Enum.find(&(&1 != nil))
  end
end
