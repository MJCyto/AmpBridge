defmodule AmpBridge.WiringDiagramManager do
  @moduledoc """
  Manages wiring diagram configurations for different cable types.
  """

  @rs232_functions [
    "RX",
    "TX",
    "GND",
    "DTR",
    "DSR",
    "RTS",
    "CTS",
    "DCD"
  ]

  @max_wires 8

  def get_rs232_functions, do: @rs232_functions

  def get_max_wires, do: @max_wires

  def create_cable_config do
    %{
      cable_1: %{wires: create_empty_wire_array(), device_name: ""},
      cable_2: %{wires: create_empty_wire_array(), device_name: ""}
    }
  end

  defp create_empty_wire_array do
    List.duplicate(nil, @max_wires)
  end

  def assign_wire_function(config, cable_id, wire_position, function)
      when wire_position in 1..@max_wires do
    cable_key = String.to_atom("cable_#{cable_id}")
    wire_index = wire_position - 1

    # Check if function is already assigned to another wire in the same cable
    current_cable =
      Map.get(config, cable_key, %{wires: create_empty_wire_array(), device_name: ""})

    current_wires = Map.get(current_cable, :wires, create_empty_wire_array())

    if function_already_assigned?(current_wires, function) do
      {:error, "Function #{function} is already assigned to another wire"}
    else
      # Update the wire array
      updated_wires = List.replace_at(current_wires, wire_index, function)
      updated_cable = Map.put(current_cable, :wires, updated_wires)
      updated_config = Map.put(config, cable_key, updated_cable)
      {:ok, updated_config}
    end
  end

  def clear_wire_function(config, cable_id, wire_position) when wire_position in 1..@max_wires do
    cable_key = String.to_atom("cable_#{cable_id}")
    wire_index = wire_position - 1

    current_cable =
      Map.get(config, cable_key, %{wires: create_empty_wire_array(), device_name: ""})

    current_wires = Map.get(current_cable, :wires, create_empty_wire_array())
    updated_wires = List.replace_at(current_wires, wire_index, nil)
    updated_cable = Map.put(current_cable, :wires, updated_wires)
    updated_config = Map.put(config, cable_key, updated_cable)

    {:ok, updated_config}
  end

  def get_available_functions(config, cable_id, wire_position) do
    cable_key = String.to_atom("cable_#{cable_id}")

    current_cable =
      Map.get(config, cable_key, %{wires: create_empty_wire_array(), device_name: ""})

    current_wires = Map.get(current_cable, :wires, create_empty_wire_array())

    # Get functions already assigned in this cable (excluding current wire)
    assigned_functions =
      current_wires
      |> Enum.with_index()
      |> Enum.reject(fn {_function, index} -> index == wire_position - 1 end)
      |> Enum.map(fn {function, _index} -> function end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    # Return functions that aren't already assigned
    @rs232_functions
    |> Enum.reject(fn function -> MapSet.member?(assigned_functions, function) end)
  end

  def get_all_functions_with_status(config, cable_id, wire_position) do
    cable_key = String.to_atom("cable_#{cable_id}")

    current_cable =
      Map.get(config, cable_key, %{wires: create_empty_wire_array(), device_name: ""})

    current_wires = Map.get(current_cable, :wires, create_empty_wire_array())

    # Get functions already assigned in this cable (excluding current wire)
    assigned_functions =
      current_wires
      |> Enum.with_index()
      |> Enum.reject(fn {_function, index} -> index == wire_position - 1 end)
      |> Enum.map(fn {function, _index} -> function end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    # Return all functions with their availability status
    @rs232_functions
    |> Enum.map(fn function ->
      {function, !MapSet.member?(assigned_functions, function)}
    end)
  end

  def update_device_name(config, cable_id, device_name) do
    cable_key = String.to_atom("cable_#{cable_id}")

    current_cable =
      Map.get(config, cable_key, %{wires: create_empty_wire_array(), device_name: ""})

    updated_cable = Map.put(current_cable, :device_name, device_name)
    updated_config = Map.put(config, cable_key, updated_cable)
    {:ok, updated_config}
  end

  def get_device_name(config, cable_id) do
    cable_key = String.to_atom("cable_#{cable_id}")

    current_cable =
      Map.get(config, cable_key, %{wires: create_empty_wire_array(), device_name: ""})

    device_name = Map.get(current_cable, :device_name, "")
    if device_name == "" or device_name == nil, do: "Device #{cable_id}", else: device_name
  end

  defp function_already_assigned?(cable_array, function) do
    function in cable_array
  end

  @doc """
  Creates a TIA B wiring configuration for side 1 (cable_1).
  TIA B standard pin assignments:
  Pin 1: White/Orange, Pin 2: Orange, Pin 3: White/Green, Pin 4: Blue
  Pin 5: White/Blue, Pin 6: Green, Pin 7: White/Brown, Pin 8: Brown
  """
  def create_tia_b_wiring do
    %{
      cable_1: %{
        wires: ["TX+", "TX-", "RX+", "NC", "NC", "RX-", "NC", "NC"],
        device_name: ""
      },
      cable_2: %{wires: create_empty_wire_array(), device_name: ""}
    }
  end

  @doc """
  Generates side 2 wiring based on side 1 connections.
  Handles proper signal swapping for RX/TX pairs and other signal types.
  """
  def generate_side2_from_side1(config) do
    side1_wires = Map.get(config, :cable_1, %{wires: create_empty_wire_array()}).wires

    # Create mapping for signal swapping
    signal_swap_map = %{
      "RX+" => "TX+",
      "RX-" => "TX-",
      "TX+" => "RX+",
      "TX-" => "RX-",
      "RX" => "TX",
      "TX" => "RX",
      "DTR" => "DSR",
      "DSR" => "DTR",
      "RTS" => "CTS",
      "CTS" => "RTS",
      # DCD typically stays the same
      "DCD" => "DCD",
      # Ground always stays the same
      "GND" => "GND",
      # Not connected stays the same
      "NC" => "NC"
    }

    # Generate side 2 by swapping signals appropriately
    side2_wires =
      side1_wires
      |> Enum.map(fn
        nil -> nil
        signal -> Map.get(signal_swap_map, signal, signal)
      end)

    # Update the config with side 2 wiring
    updated_cable_2 = Map.put(config.cable_2, :wires, side2_wires)
    Map.put(config, :cable_2, updated_cable_2)
  end

  @doc """
  Generates a complete wiring diagram with TIA B on side 1 and
  corresponding connections on side 2 with proper signal swapping.
  """
  def generate_wiring_diagram do
    config = create_tia_b_wiring()
    generate_side2_from_side1(config)
  end

  @doc """
  Gets the wire color for a given position based on TIA B standard.
  """
  def get_tia_b_wire_color(position) when position in 1..8 do
    case position do
      1 -> "white-orange"
      2 -> "orange"
      3 -> "white-green"
      4 -> "blue"
      5 -> "white-blue"
      6 -> "green"
      7 -> "white-brown"
      8 -> "brown"
    end
  end

  @doc """
  Gets the signal function for a given position based on TIA B standard.
  """
  def get_tia_b_signal_function(position) when position in 1..8 do
    case position do
      # Transmit Data +
      1 -> "TX+"
      # Transmit Data -
      2 -> "TX-"
      # Receive Data +
      3 -> "RX+"
      # Not Connected
      4 -> "NC"
      # Not Connected
      5 -> "NC"
      # Receive Data -
      6 -> "RX-"
      # Not Connected
      7 -> "NC"
      # Not Connected
      8 -> "NC"
    end
  end
end
