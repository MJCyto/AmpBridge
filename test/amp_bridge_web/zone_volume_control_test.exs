defmodule AmpBridgeWeb.ZoneVolumeControlTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  test "selects a stored source name in the source dropdown" do
    html =
      render_component(&AmpBridgeWeb.ZoneVolumeControl.zone_volume_control/1,
        zone: 0,
        adapter_connected: true,
        adapter: "adapter_1",
        sources: ["Wiim", "Zenbook"],
        current_source: "Zenbook"
      )

    assert html =~ ~s(<option value="Source 2" selected="selected">Zenbook</option>)
    refute html =~ ~s(<option value="Off" selected="selected">Off</option>)
  end

  test "continues to select legacy Source N state values" do
    html =
      render_component(&AmpBridgeWeb.ZoneVolumeControl.zone_volume_control/1,
        zone: 0,
        adapter_connected: true,
        adapter: "adapter_1",
        sources: ["Wiim", "Zenbook"],
        current_source: "Source 2"
      )

    assert html =~ ~s(<option value="Source 2" selected="selected">Zenbook</option>)
  end
end
