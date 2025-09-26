defmodule AmpBridge.Constants do
  @moduledoc """
  Constants used throughout the AmpBridge application.
  """

  @doc """
  Device types supported by the system.
  These constants are used for both frontend display and backend validation.
  """
  def device_types do
    [
      %{
        value: "matrix_amplifier",
        label: "Matrix Amplifier",
        description: "Multi-zone amplifier with matrix switching capabilities"
      },
      %{
        value: "multi_zone_amplifier",
        label: "Multi-Zone Amplifier",
        description: "Traditional multi-zone power amplifier"
      },
      %{
        value: "matrix_controller",
        label: "Matrix Controller",
        description: "Audio matrix controller without built-in amplification"
      },
      %{
        value: "multi_zone_controller",
        label: "Multi-Zone Controller",
        description: "Multi-zone controller without built-in amplification"
      },
      %{
        value: "smart_home_controller",
        label: "Smart Home Controller",
        description: "Smart home audio controller with automation features"
      }
    ]
  end

  @doc """
  Get device type values for backend validation.
  """
  def device_type_values do
    device_types()
    |> Enum.map(& &1.value)
  end

  @doc """
  Get device type by value.
  """
  def get_device_type(value) do
    Enum.find(device_types(), &(&1.value == value))
  end

  @doc """
  Get device type label by value.
  """
  def get_device_type_label(value) do
    case get_device_type(value) do
      %{label: label} -> label
      nil -> "Unknown"
    end
  end
end
