defmodule AmpBridgeWeb.EthDiagramLive.Index do
  use AmpBridgeWeb, :live_view

  # Ethernet wire colors (T568B standard)
  @wire_colors [
    %{id: 1, color: "white-orange", bg_color: "#FFE4B5", text_color: "#8B4513"},
    %{id: 2, color: "orange", bg_color: "#FFA500", text_color: "#FFFFFF"},
    %{id: 3, color: "white-green", bg_color: "#F0FFF0", text_color: "#006400"},
    %{id: 4, color: "blue", bg_color: "#0000FF", text_color: "#FFFFFF"},
    %{id: 5, color: "white-blue", bg_color: "#F0F8FF", text_color: "#0000FF"},
    %{id: 6, color: "green", bg_color: "#008000", text_color: "#FFFFFF"},
    %{id: 7, color: "white-brown", bg_color: "#F5F5DC", text_color: "#8B4513"},
    %{id: 8, color: "brown", bg_color: "#8B4513", text_color: "#FFFFFF"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    # Start with empty configuration
    wiring_config = AmpBridge.WiringDiagramManager.create_cable_config()

    {:ok,
     assign(socket,
       page_title: "Ethernet Diagram",
       # Map of wire_id => {end: :left|:right, position: 1-8}
       connections: %{},
       left_connector: %{wires: @wire_colors},
       right_connector: %{wires: @wire_colors},
       # Cable configuration with wire function assignments
       cable_config: wiring_config
     )}
  end

  @impl true
  def handle_event(
        "wire_dropped",
        %{"wire_id" => wire_id, "end" => end_side, "position" => position},
        socket
      ) do
    wire_id = String.to_integer(wire_id)
    position = String.to_integer(position)
    end_side = String.to_atom(end_side)

    # Update connections
    new_connections =
      Map.put(socket.assigns.connections, wire_id, %{
        end: end_side,
        position: position
      })

    {:noreply, assign(socket, connections: new_connections)}
  end

  @impl true
  def handle_event(
        "function_changed",
        %{"position" => position, "cable-id" => cable_id, "function" => value},
        socket
      ) do
    IO.puts("=== FUNCTION_CHANGED RECEIVED IN PARENT ===")
    IO.puts("Position: #{position}")
    IO.puts("Cable ID: #{cable_id}")
    IO.puts("Value: #{value}")

    position = String.to_integer(position)
    cable_id = String.to_integer(cable_id)

    case value do
      "" ->
        # Clear the function
        {:ok, updated_config} =
          AmpBridge.WiringDiagramManager.clear_wire_function(
            socket.assigns.cable_config,
            cable_id,
            position
          )

        {:noreply, assign(socket, cable_config: updated_config)}

      function ->
        # Assign the function
        case AmpBridge.WiringDiagramManager.assign_wire_function(
               socket.assigns.cable_config,
               cable_id,
               position,
               function
             ) do
          {:ok, updated_config} ->
            {:noreply, assign(socket, cable_config: updated_config)}

          {:error, _message} ->
            # Could show a flash message here
            {:noreply, socket}
        end
    end
  end

  @impl true
  def handle_event("wire_removed", %{"wire_id" => wire_id}, socket) do
    new_connections = Map.delete(socket.assigns.connections, wire_id)
    {:noreply, assign(socket, connections: new_connections)}
  end

  @impl true
  def handle_event("clear_connections", _params, socket) do
    {:noreply, assign(socket, connections: %{})}
  end

  @impl true
  def handle_event(
        "update_device_name",
        %{"cable-id" => cable_id, "device_name" => device_name},
        socket
      ) do
    IO.puts("=== UPDATE_DEVICE_NAME RECEIVED ===")
    IO.puts("Cable ID: #{cable_id}")
    IO.puts("Device Name: #{device_name}")

    cable_id = String.to_integer(cable_id)

    {:ok, updated_config} =
      AmpBridge.WiringDiagramManager.update_device_name(
        socket.assigns.cable_config,
        cable_id,
        device_name
      )

    {:noreply, assign(socket, cable_config: updated_config)}
  end

  @impl true
  def handle_event("reset_to_standard", _params, socket) do
    # Reset to TIA B standard with proper signal swapping
    wiring_config = AmpBridge.WiringDiagramManager.generate_wiring_diagram()

    # Generate connections based on the wiring config
    standard_connections =
      socket.assigns.left_connector.wires
      |> Enum.with_index(1)
      |> Enum.map(fn {wire, position} -> {wire.id, %{end: :right, position: position}} end)
      |> Map.new()

    {:noreply, assign(socket, connections: standard_connections, cable_config: wiring_config)}
  end

  @impl true
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
end
